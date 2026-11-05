#!/usr/bin/env bash
# One-off: run repo-rename_playbook.yml (bash_configs -> homelab) on every
# inventory. Extra arguments go to ansible-playbook, e.g.
#   ./repo-rename.sh --check
#   ./repo-rename.sh -e repo_rename_cleanup=true
set -euo pipefail
# NAS has no en_US.UTF-8, and ansible refuses to start with an unusable locale.
export LC_ALL=C.utf8

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# The NAS run moves the checkout this script lives in. A local ansible module
# fails if its working directory disappears, so work from / with absolute paths.
cd /

become_args=()
if [[ -z "${ANSIBLE_BECOME_PASSWORD_FILE:-}" ]]; then
  become_args=(--ask-become-pass)
fi

# NAS last: its run moves the checkout this script lives in.
for inventory in proxmox-vms ovh nas-local; do
  printf '\n=== %s\n' "$inventory"
  ansible-playbook -i "$script_dir/inventory/$inventory.yml" \
    "$script_dir/repo-rename_playbook.yml" "${become_args[@]}" "$@"
done
