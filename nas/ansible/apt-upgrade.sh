#!/usr/bin/env -S LC_ALL=C.utf8 bash
set -euo pipefail
export LC_ALL=C.utf8

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$script_dir"

run_ubuntu_repo_playbook() {
  local host=$1
  local mode=$2
  local series=$3

  printf '\nSudo password for %s (Ubuntu repository %s):\n' "$host" "$mode"
  ansible-playbook -i inventory/proxmox-vms.yml ubuntu-release-repositories_playbook.yml \
    --limit "$host" -e "ubuntu_repo_mode=$mode" -e "ubuntu_target_series=$series" \
    --ask-become-pass
}

for inventory_file in inventory/proxmox-vms.yml inventory/ovh.yml; do
  inventory_hosts=$(ansible-inventory -i "$inventory_file" --list |
    jq -r '[.[] | objects | .hosts[]?] | unique | join(", ")')
  printf '\nSudo password for hosts in %s: %s\n' "$inventory_file" "$inventory_hosts"
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

  current_series=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" \
    '. /etc/os-release; printf %s "$VERSION_CODENAME"')
  [[ "$current_series" =~ ^[a-z]+$ ]] || {
    printf 'Invalid installed Ubuntu series for %s: %s\n' "$host" "$current_series" >&2
    exit 1
  }
  run_ubuntu_repo_playbook "$host" resume "$current_series"

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

  run_ubuntu_repo_playbook "$host" plan "$target_series"

  if [[ ! -t 0 || ! -t 1 ]]; then
    printf 'An interactive terminal is required to approve and run the Ubuntu release upgrade.\n' >&2
    continue
  fi
  read -r -p "Upgrade $host to Ubuntu $target_series now? [y/N] " answer
  case "$answer" in
    y|Y|yes|YES|Yes) ;;
    *) printf 'Skipped Ubuntu release upgrade on %s.\n' "$host"; continue ;;
  esac

  run_ubuntu_repo_playbook "$host" quiet "$target_series"

  upgrade_result=0
  printf '\nSudo password for %s (interactive Ubuntu release upgrade):\n' "$host"
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

  run_ubuntu_repo_playbook "$host" apply "$target_series"
done
