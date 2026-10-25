# Storage I/O incident — 2026-10-25

Recorded **2026-10-25 15:52 UTC / 16:52 CET**. Incident remains open.
This is an observation/action log, not a completed repair or expansion approval.
Times below are CET (UTC+1) unless explicitly marked UTC.

## Confirmed NVMe temperature alarm on proxmox2-old

At approximately **16:52 CET**, read-only sysfs inspection returned:

```text
/sys/class/hwmon/hwmon1/name = nvme
temp1_label = Composite
temp1_input = 73850
temp1_max   = 69850
temp1_crit  = 79850
temp1_alarm = 1
temp2_label = Sensor 1
temp2_input = 93850
```

Thus composite temperature was **73.85 C**, above the exposed **69.85 C high
threshold**, and the temperature alarm was asserted. The additional sensor
reported **93.85 C**. No limit was exposed for that additional sensor; do not
compare it directly with the composite channel's critical threshold.
The peer's previously inventoried root-pool device is a **Patriot M.2 P300
256GB**. The pool also backs the dedicated Longhorn zvol.

**Thermal throttling is a hypothesis, not a proven root cause.** The alarm and
high temperatures are confirmed; current throttling counters, peer SMART health,
and root-owned kernel logs have not been inspected. `temp1_alarm` maps to the
NVMe SMART temperature-warning bit in the [Linux NVMe hwmon driver](https://code.googlesource.com/linux/torvalds/linux/+/2656821f1f202d58224551b71eff41aafd1edf8b/drivers/nvme/host/hwmon.c).
Investigate cooling/airflow and obtain privileged SMART/kernel evidence before
declaring the drive healthy, failed, or repaired. Do not raise temperature limits
or disable write durability to suppress the symptoms.

## Handoff for sudo-enabled Codex on proxmox2-old — drive/kernel evidence

User requested documenting this read-only investigation for a separate Codex
session running **on proxmox2-old (10.0.0.72)**. Confirm the hostname before
collecting; this section does not authorize a reboot or configuration change.

**Task:** collect privileged NVMe SMART and kernel/k3s evidence to determine
whether thermal management, device errors/resets, or another storage problem
correlates with the observed severe I/O stalls. Preserve the original evidence
and report what is confirmed versus still uncertain.

Run in Bash, with authenticated sudo. Store raw logs privately, not in Git:

```bash
hostname -f
lsblk -o NAME,MODEL,SIZE,TYPE,MOUNTPOINTS
findmnt -T /var/lib/longhorn -o TARGET,SOURCE,FSTYPE,OPTIONS

umask 077
diagnostics_dir=$(mktemp -d /tmp/proxmox2-old-nvme.XXXXXXXX)
printf 'Evidence directory: %s\n' "$diagnostics_dir"
date -u +%FT%TZ > "$diagnostics_dir/started-utc.txt"

# /dev/nvme0n1 was the observed Patriot P300; confirm against lsblk above.
sudo timeout --kill-after=2 20 smartctl -x /dev/nvme0n1 \
  > "$diagnostics_dir/smart-before.txt" 2>&1
sudo timeout --kill-after=2 20 journalctl -k -b --since '1 hour ago' \
  -n 1500 --no-pager -o short-iso \
  > "$diagnostics_dir/kernel-journal.txt" 2>&1
sudo timeout --kill-after=2 20 journalctl -u k3s --since '1 hour ago' \
  -n 1500 --no-pager -o short-iso \
  > "$diagnostics_dir/k3s-journal.txt" 2>&1

systemctl show k3s -p ActiveState -p SubState -p NRestarts \
  > "$diagnostics_dir/k3s-state-before.txt"
cat /proc/pressure/io > "$diagnostics_dir/io-pressure-before.txt"
timeout --kill-after=2 10 zpool iostat -v -l -q 1 5 \
  > "$diagnostics_dir/zpool-latency.txt" 2>&1
timeout --kill-after=2 10 zpool status -xv \
  > "$diagnostics_dir/zpool-status.txt" 2>&1

# A second read allows comparison of thermal/error counters without a benchmark.
sleep 60
sudo timeout --kill-after=2 20 smartctl -x /dev/nvme0n1 \
  > "$diagnostics_dir/smart-after.txt" 2>&1
cat /proc/pressure/io > "$diagnostics_dir/io-pressure-after.txt"
systemctl show k3s -p ActiveState -p SubState -p NRestarts \
  > "$diagnostics_dir/k3s-state-after.txt"
date -u +%FT%TZ > "$diagnostics_dir/finished-utc.txt"
```

Check command exit status when running; a timeout or empty/partial file is **not**
evidence of a healthy drive. If `smartctl` is missing, record that and use already
installed read-only NVMe tooling if available; do not automatically install or
upgrade packages during this incident. Do not start a SMART self-test.

Inspect/report:

- Exact model, firmware, temperature channels, warning/critical thresholds, and
  SMART critical-warning flags. Compare with the sysfs alarm above. Sensor 1's
  own limit is unknown; do not apply the composite threshold to it.
- Warning/critical temperature time, thermal-management transition counts and
  total time, comparing both SMART captures. Increasing counters are stronger
  evidence than historical nonzero counters; absence of exposed counters does
  not rule out thermal effects.
- Media/data-integrity errors, available spare, percentage used, error-log
  entries, controller busy time, and whether error counters increased.
- Kernel messages for NVMe timeout, controller reset, aborted I/O, PCIe/AER
  errors, filesystem errors, hung tasks, OOM, and read-only remounts. Preserve
  the full bounded journal capture; do not retain only matching lines.
- Correlation with k3s WAL-fsync delays, lost leadership/restarts, I/O PSI and
  actual interval queue/latency rows. The first `zpool iostat` row is since boot.

Append a timestamped **summary** and the private evidence directory to this log.
State whether thermal management was observed actively increasing, whether
device/kernel errors were present, and which facts remain unverified. Do not
commit raw logs, environment variables, kubeconfigs or Secrets. The broader
[host collector](collect-host-storage-diagnostics.sh) is also available if this
checkout contains it; the focused commands above cover the requested point 2.

**Leave workload scaling to the coordinating session.** Several applications
are deliberately stopped and another scale-down retry may be active (see below).
Do not restart them, alter Fleet, force-detach volumes, reduce replicas, reset
etcd, run a disk benchmark, run filesystem repair, change thermal limits/fsync,
or resize storage as part of evidence collection. Report back before proposing
changes; no root cause or repair is established by the current alarm alone.

## Symptoms and observed trend

- Both k3s servers repeatedly lost controller leadership and restarted; both
  APIs repeatedly failed etcd readiness. This is a two-voter etcd cluster:
  both voters are required for quorum.
- Earlier proxmox3 WAL flushes took **40.4 s** and **9.3 s**. Its local ZFS pool
  reported healthy and NVMe SMART showed zero media/data-integrity errors in
  that earlier inspection. That does not establish peer SMART health.
- Before the peer reboot, SSH/Tailscale sessions and the Proxmox web service
  intermittently stalled even while LAN ping and TCP port 22 responded.
- User issued `sudo halt`, then reported rebooting/powering the peer back on.
  At **16:12 CET**, LAN SSH worked and peer uptime was about two minutes.
  The agent did not reboot either host. Proxmox3 was left running.
- The peer reboot did **not** produce sustained recovery. Its k3s restart
  count subsequently reached **8** by approximately **16:50 CET**. Proxmox3's
  last observed count in this period was **47**.
- Peer I/O PSI repeatedly reached **90–100% some** and **70–97% full**.
  Low available throughput did not mean the disk was healthy: interval samples
  showed approximately **5,000 synchronous writes queued**, **25 s total write
  waits**, and later **14 s waits with ~687 writes queued**.
- At **16:38 CET**, peer pressure briefly improved to **21.72% some / 13.19%
  full**, queues drained, and interval write waits were approximately
  **0.7–11 ms**. At **16:39 CET**, pressure was near zero, but k3s restarted.
  Heavy pressure returned afterward. Do not treat that brief window as repair.
- Around **16:51 CET**, a five-second ZFS dataset-counter sample showed only
  ~321 KB/s root-dataset reads and ~3.3 KB/s Longhorn zvol writes while the peer
  remained under severe pressure. Queues, latency, temperatures and throughput
  must be assessed together. Peer `zpool status -xv` reported healthy; this
  does not rule out latency or thermal problems.

For `zpool iostat`, the first row is a since-boot average; interval rows supplied
the short-window queue/latency measurements above. PSI percentages describe time
tasks are stalled, not disk bandwidth utilization.

## Completed load-reduction actions — restore deliberately

User explicitly authorized the following runtime-only stops. **Fleet files were
not edited.** Kubernetes changes can be reverted by Fleet reconciliation.

| Host | Workload | Confirmed action/status |
| --- | --- | --- |
| proxmox2-old | Docker `home-assistant-watchdog-springboot-1` | Stopped; exit 143 confirmed. |
| proxmox2-old | Docker `scrutiny` | Stopped; exit 0 confirmed. |
| proxmox3 | Docker `nubile` | Stopped; exit 0 confirmed. |
| proxmox3 | Docker `emby` | Initially retained, then stopped on subsequent user instruction; exit 0 confirmed. |
| proxmox3 | `apps-sonarr/deployment/sonarr` | Direct k3s scale to 0. |
| proxmox3 | `apps-radarr/deployment/radarr` | Direct k3s scale to 0. |
| proxmox3 | `apps-bazarr/deployment/bazarr` | Direct k3s scale to 0. |

The three media scale requests were accepted before their pods actually stopped.
At approximately **16:43 CET**, all three Deployments were confirmed at desired
0 with no current replicas, and the local CRI inventory confirmed no running
Sonarr/Radarr/Bazarr containers. Earlier reports of accepted scaling alone were
not evidence that their disk activity had stopped.

Watchdog PostgreSQL (`home-assistant-watchdog-postgres-1`) was intentionally left
running in this batch. youtube-dl Material/MongoDB, mail, DNS, Longhorn, etcd,
k3s and Proxmox services were not stopped by these completed actions.

Local Emby reads measured ~3.2 MiB/s in one sample, but its media is NFS-backed;
its config is on the local root pool. This sample does not prove Emby caused
local-pool stalls. CPU percentages and cumulative Docker block-I/O totals likewise
do not establish which workload caused the peer's queue buildup.

Stopping these workloads did not establish sustained recovery. Proxmox3 was often
quiet afterward; the peer continued to experience severe stalls, and both hosts
still had intermittent restarts/API failures.

## Next scale-down batch — pending, not completed

User subsequently authorized continuing incremental application scale-downs and
measuring the effect. At this log's timestamp, the API had **not accepted** the
following next batch:

- `apps-youtubedl-material/deployment/youtubedl-material`
- `apps-zabbix/deployment/zabbix-zabbix-server`
- `apps-zabbix/deployment/zabbix-zabbix-web`
- `apps-zabbix/deployment/zabbix-zabbix-webservice`

Retry worker: `/tmp/longhorn-scale-io-batch.py`, invoked with Python 3. It retries
for at most 15 minutes and targets only those four Deployments through their
Scale subresources. It records pre-change replica counts and accepted updates
in private `/tmp/longhorn-io-relief-actions.jsonl` when API reads succeed.
Check that log, the worker process and actual workloads before assuming success
or starting another worker. It does not alter Fleet.

MongoDB and Zabbix PostgreSQL have **not** been stopped in this batch. Confirm
their application writers are stopped before any later graceful DB scale-down.
No subsequent library-app batch has been applied at this timestamp.

## Monitoring, evidence and expansion hold

- `/tmp/longhorn-expansion-watch.py` continuously checks both direct APIs,
  k3s state/restart counts and both hosts' I/O PSI every ~30 seconds. Its
  conservative screening window requires 10 continuous minutes with APIs ready,
  stable restart counts, and each host below 5% `some` / 2% `full` avg10 I/O PSI.
  These are local screening criteria, not vendor safety guarantees or proof of
  root-cause repair. A passing window still requires backup, replica, temperature
  and storage-inventory review before any resize.
- Existing read-only collector was run as transient
  `bookstack-control-plane-debug.service` with a 30-minute maximum lifetime.
  Private captures: `/tmp/bookstack-control-plane-debug/`. This service must not
  be assumed to still be running. The first capture at **14:17:26 CET** included
  local writes of ~66–73 MiB/s, elevated I/O PSI, and no ping loss to the peer.
- Reusable root diagnostic collector:
  [collect-host-storage-diagnostics.sh](collect-host-storage-diagnostics.sh).
  Local smoke-test output was written privately to
  `/tmp/longhorn-host-diagnostics.fURNfMd7/`.
- Peer SSH as `sup` works intermittently. General sudo requires authentication;
  root SSH was denied. Peer system journals and SMART need an authenticated sudo
  session. Existing Docker permissions permit the explicitly requested Docker
  stops; they have not been used to obtain host-root access.

**Host expansion remains blocked.** No zvol/filesystem/PVC resize, reservation
change, replica-count reduction, fsync change, datastore reset, volume deletion,
or forced storage detach was performed by this investigation.
See [expansion procedure](README-4-expand-storage.md). BookStack migration did
complete earlier; its migration success is not proof this later incident is fixed.

Before restoring stopped services, record their current state and restore them
in small groups, comparing temperatures, I/O latency/queues, PSI, replicas and
API readiness after each group. Preserve this runtime-stop inventory so the
services are not forgotten after maintenance.
