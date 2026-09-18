#!/usr/bin/env bash
# Show monitor evidence and relevant kernel records around a supplied timestamp.
set -euo pipefail

if (($# != 1)); then
  echo "Usage: $0 '2026-09-18 18:55:00 CEST'" >&2
  exit 2
fi

log_dir=/var/log/docker-resource-monitor
from=$(date -d "$1 - 10 minutes" --iso-8601=seconds)
until=$(date -d "$1 + 10 minutes" --iso-8601=seconds)
echo "Window: $from to $until"

for file in host.log containers.log events.log; do
  echo
  echo "--- $file ---"
  awk -v from="timestamp=$from" -v until="timestamp=$until" '$1 >= from && $1 <= until' "$log_dir/$file" 2>/dev/null || true
done

echo
echo '--- kernel OOM and blocked-task records ---'
journalctl -k --since "$from" --until "$until" --no-pager | grep -Ei 'oom|out of memory|killed process|hung task|blocked for more than' || true
