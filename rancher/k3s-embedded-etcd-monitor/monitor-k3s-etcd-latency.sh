#!/usr/bin/env bash

set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

output_dir="/var/log/k3s-etcd-monitor"
peer="10.0.0.20"
zpool_name="rpool"
cooldown_seconds=300
metrics_sample_seconds=15
metrics_history_minutes=40

usage() {
  cat <<'USAGE'
Usage: monitor-k3s-etcd-latency.sh [OPTIONS]

Follow the local k3s journal. On a serious embedded-etcd latency or Raft event,
write a timestamped evidence bundle containing concurrent host, ZFS, and network
samples. Stop with Ctrl-C.

The collector also keeps a small rolling history of selected etcd metrics. Each
event bundle contains the most recent pre-trigger sample, a fresh post-trigger
sample, and the counter delta between them.

Options:
  --output-dir DIRECTORY    Store captures here. Default: /var/log/k3s-etcd-monitor
  --peer ADDRESS            Other etcd member for the ping sample. Default: 10.0.0.20
  --zpool NAME              ZFS pool containing the etcd data. Default: rpool
  --cooldown-seconds N      Minimum time between captures. Default: 300
  -h, --help                Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      output_dir="${2:?--output-dir requires a directory}"
      shift 2
      ;;
    --peer)
      peer="${2:?--peer requires an address}"
      shift 2
      ;;
    --zpool)
      zpool_name="${2:?--zpool requires a pool name}"
      shift 2
      ;;
    --cooldown-seconds)
      cooldown_seconds="${2:?--cooldown-seconds requires a positive integer}"
      [[ "$cooldown_seconds" =~ ^[1-9][0-9]*$ ]] || {
        echo "ERROR: --cooldown-seconds must be a positive integer" >&2
        exit 2
      }
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

for command in journalctl vmstat zpool ping ps dmesg; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $command" >&2
    exit 1
  }
done

mkdir -p "$output_dir"
exec 9>"$output_dir/.monitor.lock"
flock -n 9 || {
  echo "ERROR: another monitor instance is already running" >&2
  exit 1
}

last_capture=0
metrics_history_dir="$output_dir/etcd-metrics-history"

collect_etcd_metrics() {
  curl --max-time 2 -fsS http://127.0.0.1:2381/metrics |
    grep -E "^(etcd_disk_wal_fsync_duration_seconds|etcd_disk_backend_commit_duration_seconds|etcd_network_peer_round_trip_time_seconds|etcd_network_peer_sent_failures_total|etcd_network_peer_received_failures_total|etcd_server_has_leader|etcd_server_leader_changes_seen_total|etcd_server_proposals_(committed|applied|pending|failed)_total)" || true
}

sample_etcd_metrics() {
  local sample temporary

  sample="$metrics_history_dir/$(date +%Y%m%dT%H%M%S%z).prom"
  temporary="$sample.tmp"
  collect_etcd_metrics >"$temporary" 2>&1
  mv "$temporary" "$sample"
  find "$metrics_history_dir" -maxdepth 1 -type f -name '*.prom' \
    -mmin "+$metrics_history_minutes" -delete
}

metrics_sampler() {
  while true; do
    sample_etcd_metrics
    sleep "$metrics_sample_seconds"
  done
}

latest_metrics_sample() {
  find "$metrics_history_dir" -maxdepth 1 -type f -name '*.prom' -printf '%f\n' |
    sort -r |
    head -n 1
}

write_metrics_delta() {
  local before="$1" after="$2"

  awk '
    FNR == NR {
      if (NF >= 2 && $1 !~ /^#/) before[$1] = $2
      next
    }
    NF >= 2 && $1 !~ /^#/ && ($1 in before) {
      printf "%s before=%s after=%s delta=%.9g\n", $1, before[$1], $2, $2 - before[$1]
    }
  ' "$before" "$after"
}

mkdir -p "$metrics_history_dir"
sample_etcd_metrics
metrics_sampler &
sampler_pid=$!
trap 'kill "$sampler_pid" 2>/dev/null || true' EXIT INT TERM

capture() {
  local event="$1"
  local now_epoch capture_dir baseline_name baseline_file

  now_epoch="$(date +%s)"
  if (( now_epoch - last_capture < cooldown_seconds )); then
    return
  fi
  last_capture="$now_epoch"
  capture_dir="$output_dir/$(date +%Y%m%dT%H%M%S%z)"
  mkdir -p "$capture_dir"

  printf '%s\n' "$event" >"$capture_dir/trigger.log"
  baseline_name="$(latest_metrics_sample)"
  if [[ -n "$baseline_name" ]]; then
    baseline_file="$metrics_history_dir/$baseline_name"
    cp "$baseline_file" "$capture_dir/etcd-metrics-before.prom"
  fi

  journalctl -u k3s -n 200 --no-pager -o short-iso >"$capture_dir/k3s-journal.log" &
  dmesg -T >"$capture_dir/kernel.log" &
  ps -eo pid,ppid,ni,pri,stat,pcpu,pmem,etime,comm,args --sort=-pcpu >"$capture_dir/processes.log" &
  vmstat 1 5 >"$capture_dir/vmstat.log" &
  zpool iostat -v "$zpool_name" 1 5 >"$capture_dir/zpool-iostat.log" &
  zpool status -xv >"$capture_dir/zpool-status.log" 2>&1 &
  {
    printf "loadavg\n"
    cat /proc/loadavg
    for resource in cpu io memory; do
      printf "\npressure:%s\n" "$resource"
      cat "/proc/pressure/$resource"
    done
  } >"$capture_dir/pressure.log" 2>&1 &
  cat /proc/spl/kstat/zfs/arcstats >"$capture_dir/zfs-arcstats.log" 2>&1 &
  {
    peer_interface="$(ip route get "$peer" | awk '{for (i = 1; i <= NF; i++) if ($i == "dev") {print $(i + 1); exit}}')"
    printf "peer=%s\ninterface=%s\n" "$peer" "$peer_interface"
    [[ -n "$peer_interface" ]] && ip -s link show dev "$peer_interface" || true
    ss -tin dst "$peer" || true
    nstat -a || true
    [[ -n "$peer_interface" ]] && ethtool -S "$peer_interface" || true
  } >"$capture_dir/network-state.log" 2>&1 &
  collect_etcd_metrics >"$capture_dir/etcd-metrics-after.prom" 2>&1 &
  ping -n -c 30 -i 0.1 "$peer" >"$capture_dir/ping-${peer}.log" 2>&1 &

  if command -v iostat >/dev/null 2>&1; then
    iostat -x 1 5 >"$capture_dir/iostat.log" &
  fi

  wait
  if [[ -f "$capture_dir/etcd-metrics-before.prom" && -f "$capture_dir/etcd-metrics-after.prom" ]]; then
    write_metrics_delta "$capture_dir/etcd-metrics-before.prom" "$capture_dir/etcd-metrics-after.prom" \
      >"$capture_dir/etcd-metrics-delta.log"
  fi
  printf 'Captured at %s\n' "$(date --iso-8601=seconds)" >"$capture_dir/complete"
  echo "Captured evidence: $capture_dir"
}

trigger_pattern='slow fdatasync|slow fsync|waiting for ReadIndex response took too long|context deadline exceeded|etcdserver: leader changed|lost leader|no leader at term|peer became inactive|failed to reach the peer URL|failed to send out heartbeat on time|took too long to execute|database space exceeded|corrupt|panic|fatal'

echo "Watching k3s journal; writing evidence bundles to $output_dir"
journalctl -fu k3s -o short-iso | while IFS= read -r line; do
  if [[ "$line" =~ $trigger_pattern ]]; then
    capture "$line"
  fi
done
