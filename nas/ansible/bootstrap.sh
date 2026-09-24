#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$script_dir"
inventory=inventory/proxmox-vms.yml
candidate=
password_vars_file=
umask 077

cleanup() {
  if [[ -n "$candidate" && -f "$candidate" ]]; then
    rm -- "$candidate"
  fi
  if [[ -n "$password_vars_file" && -f "$password_vars_file" ]]; then
    rm -- "$password_vars_file"
  fi
}
trap cleanup EXIT

for program in ansible-inventory ansible-playbook jq openssl; do
  if ! command -v "$program" >/dev/null 2>&1; then
    echo "Required program is missing: $program" >&2
    exit 1
  fi
done

for public_key in /mnt/MargokPool/home/sup/.ssh/id_ecdsa.pub /mnt/MargokPool/home/sup/.ssh/id_rsa.pub; do
  if [[ ! -r "$public_key" ]]; then
    echo "Required public key is not readable: $public_key" >&2
    exit 1
  fi
done

if [[ ! -w "$inventory" ]]; then
  echo "Inventory is not writable: $inventory" >&2
  exit 1
fi

read -r -p 'New inventory hostname (for example, proxmox6.localdomain.bnowakowski.pl): ' host
if [[ ! "$host" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
  echo 'Invalid hostname.' >&2
  exit 2
fi

read -r -p 'SSH address if different from hostname (Enter to use hostname): ' ssh_address
if [[ -n "$ssh_address" && ! "$ssh_address" =~ ^[a-zA-Z0-9][a-zA-Z0-9.:-]*$ ]]; then
  echo 'Invalid SSH address.' >&2
  exit 2
fi

read -r -p 'Root SSH port [22]: ' ssh_port
ssh_port=${ssh_port:-22}
if [[ ! "$ssh_port" =~ ^[0-9]+$ ]] || (( 10#$ssh_port < 1 || 10#$ssh_port > 65535 )); then
  echo 'SSH port must be between 1 and 65535.' >&2
  exit 2
fi

read -r -p 'Root SSH authentication, password or key [password]: ' root_auth
root_auth=${root_auth:-password}
case "$root_auth" in
  password)
    if ! command -v sshpass >/dev/null 2>&1; then
      echo 'Password-based Ansible SSH requires sshpass.' >&2
      exit 1
    fi
    auth_args=(--ask-pass)
    ;;
  key)
    auth_args=()
    ;;
  *)
    echo 'Choose password or key.' >&2
    exit 2
    ;;
esac

inventory_json=$(ansible-inventory -i "$inventory" --list)
if jq -e --arg host "$host" \
  '[.[] | objects | .hosts? | select(type == "array") | .[]] | index($host) != null' \
  >/dev/null <<<"$inventory_json"; then
  echo "Host already exists in $inventory: $host" >&2
  exit 2
fi

echo
echo "Proposed addition to $inventory:"
printf '    %s:\n' "$host"
if [[ -n "$ssh_address" ]]; then
  printf "        ansible_host: '%s'\n" "$ssh_address"
fi
if [[ "$ssh_port" != 22 ]]; then
  printf '        ansible_port: %s\n' "$ssh_port"
fi
printf '        ansible_user: root\n'
echo 'Bootstrap will connect as root, install sudo, set a password for sup, require that password for sudo, and add the local public keys.'
echo 'The root password, if used, will be requested by Ansible. Neither password will be saved in the inventory.'
read -r -p 'Add this host and run bootstrap? Type yes to continue: ' confirmation
if [[ "$confirmation" != yes ]]; then
  echo 'Cancelled; inventory was not changed.'
  exit 0
fi

read -r -s -p 'New password for sup: ' sup_password
printf '\n'
read -r -s -p 'Confirm password for sup: ' sup_password_confirm
printf '\n'
if [[ -z "$sup_password" || "$sup_password" != "$sup_password_confirm" ]]; then
  echo 'Passwords are empty or do not match; inventory was not changed.' >&2
  exit 2
fi
sup_password_hash=$(printf '%s\n' "$sup_password" | openssl passwd -6 -stdin)
unset sup_password sup_password_confirm
password_vars_file=$(mktemp --suffix=.yml /tmp/ansible-bootstrap-sup.XXXXXX)
printf 'bootstrap_sup_password_hash: "%s"\n' "$sup_password_hash" >"$password_vars_file"
unset sup_password_hash

candidate=$(mktemp --suffix=.yml "$script_dir/inventory/.proxmox-vms.XXXXXX")
cp -p -- "$inventory" "$candidate"
printf '\n    %s:\n' "$host" >>"$candidate"
if [[ -n "$ssh_address" ]]; then
  printf "        ansible_host: '%s'\n" "$ssh_address" >>"$candidate"
fi
if [[ "$ssh_port" != 22 ]]; then
  printf '        ansible_port: %s\n' "$ssh_port" >>"$candidate"
fi
printf '        ansible_user: root\n' >>"$candidate"

candidate_json=$(ansible-inventory -i "$candidate" --list)
if ! jq -e --arg host "$host" \
  '[.[] | objects | .hosts? | select(type == "array") | .[]] | index($host) != null' \
  >/dev/null <<<"$candidate_json"; then
  echo 'The proposed inventory did not parse with the new host; original inventory is unchanged.' >&2
  exit 1
fi

mv -- "$candidate" "$inventory"
candidate=
echo "Added $host to $inventory. Starting bootstrap."
if ! ansible-playbook -i "$inventory" bootstrap_playbook.yml --limit "$host" "${auth_args[@]}" --extra-vars "@$password_vars_file"; then
  echo "Bootstrap failed; ansible_user: root remains in $inventory for recovery." >&2
  exit 1
fi

echo "Bootstrap completed. Testing SSH as sup on $host."
# Extra vars override the temporary inventory ansible_user: root.
if ! ansible -i "$inventory" "$host" -e ansible_user=sup -m ping; then
  echo "sup SSH failed; ansible_user: root remains in $inventory for recovery." >&2
  exit 1
fi

candidate=$(mktemp --suffix=.yml "$script_dir/inventory/.proxmox-vms.XXXXXX")
if ! awk -v target="$host" '
  /^    [a-zA-Z0-9][a-zA-Z0-9.-]*:$/ { in_target = ($0 == "    " target ":") }
  in_target && $0 == "        ansible_user: root" {
    print "        #ansible_user: root"
    replaced++
    in_target = 0
    next
  }
  { print }
  END { if (replaced != 1) exit 1 }
' "$inventory" >"$candidate"; then
  echo "Could not safely comment ansible_user: root for $host; inventory is unchanged." >&2
  exit 1
fi
chmod --reference="$inventory" "$candidate"
candidate_json=$(ansible-inventory -i "$candidate" --list)
if ! jq -e --arg host "$host" \
  '[.[] | objects | .hosts? | select(type == "array") | .[]] | index($host) != null' \
  >/dev/null <<<"$candidate_json"; then
  echo 'The final inventory did not parse; temporary root entry remains in the original inventory.' >&2
  exit 1
fi
mv -- "$candidate" "$inventory"
candidate=
echo "Commented ansible_user: root for $host. Testing normal inventory login."
ansible -i "$inventory" "$host" -m ping
