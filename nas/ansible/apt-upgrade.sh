#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$script_dir"

for inventory_file in inventory/proxmox-vms.yml inventory/ovh.yml; do
  printf 'Upgrading hosts from %s; enter their sudo password when prompted.\n' "$inventory_file"
  ansible-playbook -i "$inventory_file" apt-upgrade_playbook.yml --ask-become-pass
done
