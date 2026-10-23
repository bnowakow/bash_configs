#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
compose_file="$script_dir/compose.yaml"
# Lock the existing file so manual and scheduled updates cannot overlap.
exec 9<"$compose_file"
if ! flock -n 9; then
  echo "An Emby/Nubile upgrade is already running; skipping."
  exit 0
fi
printf '[%s] Checking Emby and Nubile images\n' "$(date -Is)"
docker compose -f "$compose_file" config --quiet
# Complete all downloads before recreating either service.
docker compose -f "$compose_file" pull --policy always
docker compose -f "$compose_file" up -d --pull never --wait --wait-timeout 120
printf '[%s] Emby/Nubile image update completed\n' "$(date -Is)"
