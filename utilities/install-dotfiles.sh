#!/usr/bin/env bash
# Install the same dotfiles collected by sync-dotfiles.sh, without Ansible.
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "Usage: $0" >&2
  exit 2
fi

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
config="$repo_root/nas/ansible/vars/sup-dotfiles.yml"
host=$(hostname -s)
backup_dir=

read_list() {
  awk -v key="$1" '
    /^[^[:space:]#]/ { in_list = ($0 ~ "^" key ":"); next }
    in_list && /^[[:space:]]+-[[:space:]]/ { sub(/^[[:space:]]+-[[:space:]]+/, ""); gsub(/["\047]/, ""); print }
  ' "$config"
}

read_screenrc_map() {
  awk '
    /^[^[:space:]#]/ { in_list = ($0 ~ /^sup_screenrc_files:/); next }
    !in_list { next }
    /host_regex:/ { sub(/.*host_regex:[[:space:]]*/, ""); gsub(/^["\047]|["\047][[:space:]]*$/, ""); regex = $0 }
    /[[:space:]]file:/ { sub(/.*file:[[:space:]]*/, ""); gsub(/["\047]/, ""); print regex "\t" $0 }
  ' "$config"
}

install_file() {
  local source="$repo_root/$1" destination="$HOME/$2"
  if [[ -e "$destination" && "$source" -ef "$destination" ]]; then
    printf '  %s already points to the repository file, skipped\n' "$2"
    return
  fi
  if [[ -f "$destination" ]] && cmp -s "$source" "$destination"; then
    printf '  %s up to date\n' "$2"
    return
  fi
  if [[ -e "$destination" || -L "$destination" ]]; then
    if [[ -z "$backup_dir" ]]; then
      backup_dir=$(mktemp -d "$HOME/.homelab-dotfiles-backup.XXXXXX")
      printf 'Backing up existing dotfiles to %s\n' "$backup_dir"
    fi
    mv -- "$destination" "$backup_dir/$2"
  fi
  cp -- "$source" "$destination"
  chmod 0644 "$destination"
  printf '  Installed ~/%s\n' "$2"
}

printf 'Installing dotfiles from the repository on %s\n' "$host"
while IFS= read -r file; do
  install_file "$file" "$file"
done < <(read_list sup_dotfiles)

screenrc_file=
while IFS=$'\t' read -r regex file; do
  if [[ "$host" =~ $regex ]]; then
    screenrc_file=$file
    break
  fi
done < <(read_screenrc_map)

if [[ -n "$screenrc_file" ]]; then
  install_file "$screenrc_file" .screenrc
else
  printf '  No .screenrc mapping for %s; skipped\n' "$host"
fi
