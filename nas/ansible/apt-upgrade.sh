#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$script_dir"

for inventory_file in inventory/proxmox-vms.yml inventory/ovh.yml; do
  printf 'Upgrading hosts from %s; enter their sudo password when prompted.\n' "$inventory_file"
  ansible-playbook -i "$inventory_file" apt-upgrade_playbook.yml --ask-become-pass
done

# Ubuntu release upgrades are interactive and apply only to opted-in hosts.
# Debian and Proxmox release upgrades require their own procedures.
ubuntu_hosts_text=$(
  ansible-inventory -i inventory/proxmox-vms.yml --list |
    jq -r '.ubuntu_release_upgrade.hosts[]?'
)
ubuntu_hosts=()
if [[ -n "$ubuntu_hosts_text" ]]; then
  mapfile -t ubuntu_hosts <<< "$ubuntu_hosts_text"
fi

for host in "${ubuntu_hosts[@]}"; do
  if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" \
    'test "$(. /etc/os-release; printf %s "$ID")" = ubuntu'; then
    printf 'Skipping Ubuntu release check on %s: host is unreachable or is not Ubuntu.\n' "$host" >&2
    continue
  fi

  if ! release_check=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" 'do-release-upgrade -c' 2>&1); then
    printf '%s: no Ubuntu release upgrade is offered (or the check failed):\n%s\n' "$host" "$release_check"
    continue
  fi
  printf '%s:\n%s\n' "$host" "$release_check"

  target_series=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" 'python3 - target' \
    < files/ubuntu_release_repos.py)
  [[ "$target_series" =~ ^[a-z]+$ ]] || {
    printf 'Invalid Ubuntu target series for %s: %s\n' "$host" "$target_series" >&2
    exit 1
  }

  ansible-playbook -i inventory/proxmox-vms.yml ubuntu-release-repositories_playbook.yml \
    --limit "$host" -e "ubuntu_repo_mode=plan" -e "ubuntu_target_series=$target_series" \
    --ask-become-pass

  if [[ ! -t 0 || ! -t 1 ]]; then
    printf 'An interactive terminal is required to approve and run the Ubuntu release upgrade.\n' >&2
    continue
  fi
  read -r -p "Upgrade $host to Ubuntu $target_series now? [y/N] " answer
  case "$answer" in
    y|Y|yes|YES|Yes) ;;
    *) printf 'Skipped Ubuntu release upgrade on %s.\n' "$host"; continue ;;
  esac

  ansible-playbook -i inventory/proxmox-vms.yml ubuntu-release-repositories_playbook.yml \
    --limit "$host" -e "ubuntu_repo_mode=quiet" -e "ubuntu_target_series=$target_series" \
    --ask-become-pass

  upgrade_result=0
  ssh -tt -o BatchMode=yes -o ConnectTimeout=10 "$host" 'sudo do-release-upgrade' || upgrade_result=$?

  current_series=
  for attempt in {1..90}; do
    current_series=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" \
      '. /etc/os-release; printf %s "$VERSION_CODENAME"' 2>/dev/null) || current_series=
    [[ "$current_series" == "$target_series" ]] && break
    if (( upgrade_result != 255 )) && [[ -n "$current_series" ]]; then
      break
    fi
    sleep 10
  done
  if [[ "$current_series" != "$target_series" ]]; then
    printf 'Ubuntu release upgrade did not complete on %s; saved repository plan was not applied.\n' "$host" >&2
    exit 1
  fi

  ansible-playbook -i inventory/proxmox-vms.yml ubuntu-release-repositories_playbook.yml \
    --limit "$host" -e "ubuntu_repo_mode=apply" -e "ubuntu_target_series=$target_series" \
    --ask-become-pass
done
