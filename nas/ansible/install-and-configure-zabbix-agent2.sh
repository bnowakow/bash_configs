#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "Usage: $0" >&2
  exit 2
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$script_dir"

inventory=inventory/proxmox-vms.yml
temporary_become_password_file=

cleanup() {
  if [[ -n "$temporary_become_password_file" && -f "$temporary_become_password_file" ]]; then
    rm -- "$temporary_become_password_file"
  fi
}
trap cleanup EXIT

if [[ -z "${ANSIBLE_BECOME_PASSWORD_FILE:-}" ]]; then
  umask 077
  read -r -s -p 'Sudo password for sup (used on all inventory hosts): ' become_password
  printf '\n'
  if [[ -z "$become_password" ]]; then
    echo 'A sudo password is required.' >&2
    exit 2
  fi
  temporary_become_password_file=$(mktemp /tmp/ansible-become-password.XXXXXX)
  printf '%s\n' "$become_password" >"$temporary_become_password_file"
  unset become_password
  export ANSIBLE_BECOME_PASSWORD_FILE=$temporary_become_password_file
elif [[ ! -r "$ANSIBLE_BECOME_PASSWORD_FILE" ]]; then
  echo "Cannot read ANSIBLE_BECOME_PASSWORD_FILE: $ANSIBLE_BECOME_PASSWORD_FILE" >&2
  exit 2
fi

# The root-only bootstrap is a separate, one-time playbook.
for playbook in initial-config_playbook.yml git-config_playbook.yml zabbix-agent2_playbook.yml proxmox-post-install_playbook.yml; do
  ansible-playbook -i "$inventory" "$playbook"
done

# Prezto is currently configured only for proxmox5 in its playbook.
ansible-playbook -i "$inventory" proxmox-prezto_playbook.yml

# Dotfiles are for Proxmox hosts; non-Proxmox VMs are not targeted.
ansible-playbook -i "$inventory" sup-dotfiles_playbook.yml --limit 'proxmox*'

# Package and firmware upgrades remain separate because apt-upgrade_playbook.yml
# may require a reboot confirmation.
