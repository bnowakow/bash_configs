#!/usr/bin/env bash
# Read-only host diagnostics. Writes only to a newly created private directory.
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
umask 077

duration=60
interval=5
output_dir=''
peer=''
usage() {
  cat <<'EOF'
Usage: sudo bash collect-host-storage-diagnostics.sh [OPTIONS]

Run directly on each real k3s host. No reboot, benchmark, service/configuration
change, filesystem repair, or storage modification is performed.

  --duration SECONDS    Counter sampling window, 1..3600 (default: 60)
  --interval SECONDS    Sampling interval, 1..60 (default: 5)
  --peer ADDRESS       Optional other host IP/name for a bounded ping sample
  --output-dir PATH    Create this NEW directory (default: private /tmp directory)
  -h, --help           Show help without requiring root

Requires root, Python 3 and GNU timeout. Missing optional commands are recorded.
The private output includes hostnames, IPs, dataset names, and system logs;
review it before sharing. Secret objects, environment variables and full process
command lines are not collected. Commands have individual time limits; collection
can take longer than --duration while bounded metadata checks finish.
EOF
}
while (($#)); do
  case "$1" in
    --duration|--interval|--peer|--output-dir)
      (($# >= 2)) || { echo "Missing value for $1" >&2; exit 2; }
      case "$1" in
        --duration) duration=$2;;
        --interval) interval=$2;;
        --peer) peer=$2;;
        --output-dir) output_dir=$2;;
      esac
      shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; exit 2;;
  esac
done
if [[ ! $duration =~ ^[1-9][0-9]{0,3}$ ]] || ((duration > 3600)); then
  echo 'Invalid duration' >&2; exit 2
fi
if [[ ! $interval =~ ^[1-9][0-9]?$ ]] || ((interval > 60)); then
  echo 'Invalid interval' >&2; exit 2
fi
[[ -z $peer || $peer =~ ^[a-zA-Z0-9][a-zA-Z0-9.:%_-]*$ ]] || { echo 'Invalid peer address' >&2; exit 2; }
((EUID == 0)) || { echo 'Run with sudo on the actual host to read journals and process counters.' >&2; exit 1; }
for dependency in timeout python3; do
  command -v "$dependency" >/dev/null || { echo "Required command missing: $dependency" >&2; exit 1; }
done
if [[ -n $output_dir ]]; then
  mkdir -m 700 -- "$output_dir" || { echo 'Output directory must not already exist.' >&2; exit 1; }
else
  output_dir=$(mktemp -d /tmp/longhorn-host-diagnostics.XXXXXXXX)
fi
output_dir=$(cd -- "$output_dir" && pwd -P)
printf 'Collecting private diagnostics in %s\n' "$output_dir"

capture() {
  local label=$1 limit=$2 result=0
  shift 2
  {
    printf 'started=%s\n' "$(date -u +%FT%TZ)"
    if command -v "$1" >/dev/null 2>&1; then
      timeout --signal=TERM --kill-after=2 "$limit" "$@" || result=$?
    else
      echo "Optional command unavailable: $1"
      result=127
    fi
    printf '\nexit_status=%s finished=%s\n' "$result" "$(date -u +%FT%TZ)"
  } >"$output_dir/$label.txt" 2>&1
}

host_inventory() {
  capture hostname 5 hostname -f
  capture kernel-version 5 uname -a
  capture uptime 5 uptime
  capture memory 5 free -h
  capture longhorn-mount 5 findmnt -T /var/lib/longhorn -o TARGET,SOURCE,FSTYPE,OPTIONS,UUID
  capture etcd-mount 5 findmnt -T /var/lib/rancher/k3s/server/db/etcd -o TARGET,SOURCE,FSTYPE,OPTIONS
  capture filesystems 5 df -hT / /var/lib/rancher/k3s /var/lib/longhorn
  capture block-devices 5 lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL
  capture longhorn-label 5 blkid -t LABEL=longhorn
  capture processes 5 ps -eo pid,ppid,comm,stat,ni,pcpu,pmem,wchan:32 --sort=-pcpu
  capture peer-sockets 5 ss -tin '( dport = :2380 or sport = :2380 )'
  if [[ -n $peer ]]; then capture peer-ping 12 ping -n -c 10 -W 1 "$peer"; fi
}
storage_inventory() {
  capture zpool-status 10 zpool status -xv
  capture zpool-capacity 10 zpool list -p -o name,size,alloc,free,capacity,health
  capture zvols 10 zfs list -p -t volume -o name,volsize,used,available,refreservation
  capture zfs-budget 10 zfs get -Hp -t filesystem,volume -o name,property,value,source quota,refquota,reservation,refreservation,usedbysnapshots,sync,logbias,volblocksize
  capture zpool-latency 12 zpool iostat -v -l -q 1 5
  capture disk-latency 12 iostat -x -y 1 5
  local device label
  for device in /dev/nvme[0-9]*n[0-9]*; do
    [[ -b $device && ${device##*/} =~ ^nvme[0-9]+n[0-9]+$ ]] || continue
    label=${device##*/}
    capture "smart-$label" 10 smartctl -x "$device"
  done
}
service_inventory() {
  capture k3s-state-before 5 systemctl show k3s -p ActiveState -p SubState -p NRestarts -p Result -p MainPID -p ExecMainStartTimestamp -p ExecMainExitTimestamp
  capture k3s-journal 12 journalctl -u k3s --since '30 minutes ago' -n 1500 --no-pager -o short-iso
  capture kernel-journal 12 journalctl -k --since '30 minutes ago' -n 800 --no-pager -o short-iso
  capture failed-units 5 systemctl --failed --no-pager
  capture etcd-metrics 5 curl -fsS --max-time 4 http://127.0.0.1:2381/metrics
  local tls=/var/lib/rancher/k3s/server/tls/etcd
  if [[ -r $tls/client.key ]]; then
    capture etcd-status 10 etcdctl --endpoints=https://127.0.0.1:2379 --cacert="$tls/server-ca.crt" --cert="$tls/client.crt" --key="$tls/client.key" --dial-timeout=3s --command-timeout=5s endpoint status --cluster -w table
  fi
  if [[ -r /etc/rancher/k3s/k3s.yaml ]]; then
    local kube=(kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml --request-timeout=5s)
    capture api-readiness-before 8 "${kube[@]}" get --raw='/readyz?verbose'
    capture longhorn-volumes 8 "${kube[@]}" -n longhorn-system get volumes.longhorn.io -o 'custom-columns=NAME:.metadata.name,STATE:.status.state,HEALTH:.status.robustness,NODE:.status.currentNodeID,NS:.status.kubernetesStatus.namespace,PVC:.status.kubernetesStatus.pvcName,BACKUP:.status.lastBackup,BACKUP_AT:.status.lastBackupAt'
    capture longhorn-replicas 8 "${kube[@]}" -n longhorn-system get replicas.longhorn.io -o 'custom-columns=NAME:.metadata.name,VOLUME:.spec.volumeName,NODE:.spec.nodeID,STATE:.status.currentState,FAILED_AT:.spec.failedAt'
    capture longhorn-disks 8 "${kube[@]}" -n longhorn-system get nodes.longhorn.io -o json
    capture longhorn-space-policy 8 "${kube[@]}" -n longhorn-system get settings.longhorn.io storage-minimal-available-percentage storage-over-provisioning-percentage -o 'custom-columns=NAME:.metadata.name,VALUE:.value'
  fi
}

host_inventory & host_pid=$!
storage_inventory & storage_pid=$!
service_inventory & service_pid=$!

# Counter sampling adds no artificial disk traffic. Process names only, no args.
python3 - "$duration" "$interval" >"$output_dir/counter-samples.jsonl" 2>"$output_dir/sampler-errors.txt" <<'PY' &
import datetime, glob, json, pathlib, sys, time
duration, interval = map(int, sys.argv[1:])
def read(path):
    try:
        return pathlib.Path(path).read_text()
    except OSError:
        return ''
def snapshot():
    procs = {}
    for path in glob.glob('/proc/[0-9]*/io'):
        pid = path.split('/')[2]
        try:
            fields = dict(line.split(':', 1) for line in read(path).splitlines())
            # /proc/PID/io may include reaped children: identity and start time
            # avoid PID reuse, but deltas are attribution clues, not proof.
            stat = read('/proc/' + pid + '/stat').rsplit(')', 1)[1].split()
            procs[pid] = {'name': read('/proc/' + pid + '/comm').strip(),
                          'start': stat[19],
                          'read': int(fields['read_bytes']),
                          'write': int(fields['write_bytes'])}
        except (KeyError, ValueError, IndexError):
            continue
    datasets = {}
    for path in glob.glob('/proc/spl/kstat/zfs/*/objset-*'):
        fields = {parts[0]: parts[2] for line in read(path).splitlines()
                  if len(parts := line.split()) == 3}
        if 'dataset_name' in fields:
            datasets[fields['dataset_name']] = {
                key: int(fields.get(key, 0)) for key in ('nread', 'nwritten', 'reads', 'writes')}
    return procs, datasets
started = previous_time = time.monotonic()
previous_procs, previous_datasets = snapshot()
while time.monotonic() - started < duration:
    time.sleep(min(interval, max(0, duration - (time.monotonic() - started))))
    procs, datasets = snapshot()
    now = time.monotonic()
    elapsed = now - previous_time
    process_io = []
    for pid, values in procs.items():
        old = previous_procs.get(pid)
        if old is None or old['start'] != values['start']:
            continue
        rd, wr = (max(0, values[k] - old[k]) / elapsed for k in ('read', 'write'))
        if rd + wr:
            process_io.append({'pid': int(pid), 'name': values['name'],
                               'read_bytes_s': round(rd), 'write_bytes_s': round(wr)})
    dataset_io = []
    for name, values in datasets.items():
        old = previous_datasets.get(name)
        if old is not None:
            dataset_io.append({'dataset': name, **{
                key + '_s': round(max(0, value - old[key]) / elapsed, 2)
                for key, value in values.items()}})
    sample = {
        'time': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'elapsed_seconds': round(now - started, 2),
        'pressure': {key: read('/proc/pressure/' + key).strip() for key in ('io', 'cpu', 'memory')},
        'loadavg': read('/proc/loadavg').strip(),
        'diskstats': read('/proc/diskstats'),
        'arcstats': read('/proc/spl/kstat/zfs/arcstats'),
        'temperatures_millidegrees_c': {
            path: read(path).strip() for path in glob.glob('/sys/class/hwmon/hwmon*/temp*_input')},
        'top_process_io': sorted(process_io, key=lambda row: row['read_bytes_s'] + row['write_bytes_s'], reverse=True)[:20],
        'dataset_io': dataset_io,
    }
    print(json.dumps(sample), flush=True)
    previous_procs, previous_datasets, previous_time = procs, datasets, now
PY
sampler_pid=$!
result=0
for job_pid in "$host_pid" "$storage_pid" "$service_pid" "$sampler_pid"; do
  wait "$job_pid" || result=1
done
capture k3s-state-after 5 systemctl show k3s -p ActiveState -p SubState -p NRestarts -p Result -p MainPID
if [[ -r /etc/rancher/k3s/k3s.yaml ]]; then
  capture api-readiness-after 8 kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml --request-timeout=5s get --raw='/readyz?verbose'
fi
cat >"$output_dir/README.txt" <<'EOF'
Read-only host diagnostic capture. All timestamps use UTC where specified.
Check exit_status in each text file: 124 means timed out, 127 means unavailable.
A successful collector exit does not imply healthy services; inspect each file.
Compare k3s-state-before/after and api-readiness-before/after. Counter samples
contain process I/O rates, ZFS dataset rates, diskstats, PSI and ARC counters.
/proc/PID/io may include reaped child activity: use it as a clue, not proof.
The first zpool iostat row is since boot; subsequent rows are interval samples.
Backup names/timestamps alone do not prove independent restore verification.
No automatic repair or expansion recommendation is made by this collector.
Private system logs can contain sensitive application details; review before sharing.
EOF
printf 'finished_utc=%s collector_status=%s\n' "$(date -u +%FT%TZ)" "$result" >"$output_dir/complete.txt"
printf 'Finished. Review %s (per-command failures/timeouts are recorded).\n' "$output_dir"
exit "$result"
