#!/usr/bin/env bash
set -euo pipefail

if (( $# != 0 )); then
  printf 'Usage: %s\n' "$0" >&2
  exit 2
fi

sudo find /mnt/PlexPool/plex -mindepth 1 -maxdepth 1 -type d \
  \( -name '*TV-Series*' -o -name '*Movies*' -o -name '*Audiobooks*' -o -name '*Books*' \) \
  -exec chown -R apps:apps -- {} +
