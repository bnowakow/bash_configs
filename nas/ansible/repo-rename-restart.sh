#!/usr/bin/env bash
# Temporary: run repo-rename-restart_playbook.yml on every inventory.
# Extra arguments go to ansible-playbook, e.g. --check or --limit transmission.
set -euo pipefail
export LC_ALL=C.utf8

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd /

become_args=()
if [[ -z "${ANSIBLE_BECOME_PASSWORD_FILE:-}" ]]; then
  become_args=(--ask-become-pass)
fi

for inventory in proxmox-vms ovh nas-local; do
  printf '\n=== %s (become password for this inventory)\n' "$inventory"
  ansible-playbook -i "$script_dir/inventory/$inventory.yml" \
    "$script_dir/repo-rename-restart_playbook.yml" "${become_args[@]}" "$@"
done
