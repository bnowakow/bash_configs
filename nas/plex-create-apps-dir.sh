#!/usr/bin/env bash
set -euo pipefail

if (( $# != 0 )); then
  printf 'Usage: %s\n' "$0" >&2
  exit 2
fi

plex_root=$(realpath -e -- /mnt/PlexPool/plex)
read -r -p "Directory under $plex_root (relative or absolute path): " directory
if [[ -z $directory ]]; then
  printf 'A directory is required.\n' >&2
  exit 2
fi

if [[ $directory != /* ]]; then
  directory=$plex_root/$directory
fi
directory=$(realpath -m -- "$directory")
case $directory in
  "$plex_root"/*) ;;
  *)
    printf 'Directory must be inside %s.\n' "$plex_root" >&2
    exit 2
    ;;
esac

sudo mkdir -p -- "$directory"
sudo chown -R -- apps:apps "$directory"
printf 'Created and assigned apps:apps to %s\n' "$directory"
