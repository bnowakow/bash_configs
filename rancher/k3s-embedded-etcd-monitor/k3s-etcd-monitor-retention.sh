#!/usr/bin/env bash

set -euo pipefail

monitor_dir="/var/log/k3s-etcd-monitor"
max_bytes=$((10 * 1000 * 1000 * 1000))
lock_file="$monitor_dir/.retention.lock"

mkdir -p "$monitor_dir"
exec 9>"$lock_file"
flock -n 9 || exit 0

archive_completed_bundles() {
  local bundle archive temporary base

  while IFS= read -r -d '' bundle; do
    base="$(basename "$bundle")"
    archive="$monitor_dir/$base.tar.gz"
    [[ -e "$archive" ]] && continue
    [[ -f "$bundle/complete" ]] || continue

    temporary="$archive.tmp.$$"
    tar -C "$monitor_dir" -czf "$temporary" -- "$base"
    mv "$temporary" "$archive"
    rm -rf -- "$bundle"
  done < <(find "$monitor_dir" -mindepth 1 -maxdepth 1 -type d -name '20*' -print0)
}

usage_bytes() {
  du -sb "$monitor_dir" | awk '{print $1}'
}

oldest_archive() {
  find "$monitor_dir" -mindepth 1 -maxdepth 1 -type f -name '20*.tar.gz' \
    -printf '%T@ %p\n' | sort -n | head -n 1 | cut -d' ' -f2-
}

archive_completed_bundles

while (( $(usage_bytes) > max_bytes )); do
  archive="$(oldest_archive)"
  [[ -n "$archive" ]] || break
  rm -f -- "$archive"
done
