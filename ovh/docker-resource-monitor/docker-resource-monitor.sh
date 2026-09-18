#!/usr/bin/env bash
# Record lightweight host and Docker snapshots every 30 seconds.
set -uo pipefail

log_dir=/var/log/docker-resource-monitor
host_log="$log_dir/host.log"
containers_log="$log_dir/containers.log"
events_log="$log_dir/events.log"
error_log="$log_dir/service-errors.log"

install -d -m 0755 "$log_dir"
exec 9>/run/docker-resource-monitor.lock
flock -n 9 || exit 0

timestamp() { date --iso-8601=seconds; }

sample() {
  local now load mem_available swap_used root_used root_size d_tasks stats
  now=$(timestamp)
  load=$(cut -d ' ' -f1-3 /proc/loadavg)
  mem_available=$(awk '/MemAvailable:/ {print $2 * 1024}' /proc/meminfo)
  swap_used=$(free -b | awk '/^Swap:/ {print $3}')
  read -r root_size root_used < <(df -B1 --output=size,used / | awk 'NR == 2 {print $1, $2}')
  d_tasks=$(ps -eo stat= | awk '$1 ~ /^D/ {count++} END {print count + 0}')
  printf 'timestamp=%s type=host load_1=%s load_5=%s load_15=%s mem_available_bytes=%s swap_used_bytes=%s root_used_bytes=%s root_size_bytes=%s uninterruptible_tasks=%s\n' \
    "$now" $load "$mem_available" "$swap_used" "$root_used" "$root_size" "$d_tasks" >> "$host_log"

  # Docker's CLI performs one non-streaming cgroup read per running container.
  stats=$(docker stats --no-stream --format 'name={{.Name}} cpu={{.CPUPerc}} mem={{.MemUsage}} net={{.NetIO}} block={{.BlockIO}} pids={{.PIDs}}' 2>>"$error_log") || stats='docker_stats_unavailable'
  while IFS= read -r line; do
    line=${line// \/ /\/}
    line=${line// /_}
    printf 'timestamp=%s type=stats %s\n' "$now" "$line" >> "$containers_log"
  done <<< "$stats"

  while IFS=' ' read -r id name; do
    docker inspect --format "timestamp=$now type=state name={{.Name}} status={{.State.Status}} running={{.State.Running}} restart_count={{.RestartCount}} oom_killed={{.State.OOMKilled}} started_at={{.State.StartedAt}} memory_limit_bytes={{.HostConfig.Memory}} cpu_nano={{.HostConfig.NanoCpus}} pids_limit={{.HostConfig.PidsLimit}}" "$id" 2>>"$error_log" >> "$containers_log" || true
  done < <(docker ps -a --format '{{.ID}} {{.Names}}' 2>>"$error_log")
}

collect_events() {
  while true; do
    docker events --filter type=container --filter event=start --filter event=die --filter event=oom --filter event=kill --filter event=restart --filter event=destroy --format 'action={{.Action}} name={{.Actor.Attributes.name}} image={{.Actor.Attributes.image}} exit_code={{.Actor.Attributes.exitCode}}' 2>>"$error_log" |
      while IFS= read -r event; do
        printf 'timestamp=%s type=docker_event %s\n' "$(timestamp)" "$event" >> "$events_log"
      done
    sleep 2
  done
}

collect_events &
event_pid=$!
trap 'kill "$event_pid" 2>/dev/null || true; exit 0' INT TERM EXIT

while true; do
  sample
  sleep 30
done
