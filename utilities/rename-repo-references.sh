#!/usr/bin/env bash
# Rewrites bash_configs/bash-configs -> homelab in tracked files (paths, GitHub
# URLs, variable names, prose). Run it after nas/ansible/repo-rename.sh has
# moved the checkouts, then review the diff and commit.
#   --dry-run  list matching lines without changing anything
set -euo pipefail

old_name=bash_configs
new_name=homelab

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

# The migration itself must keep the old name, and incident logs/handoffs are
# historical records of what ran at the time.
pathspec=(
  .
  ':(exclude)nas/ansible/repo-rename*'
  ':(exclude)utilities/rename-repo-references.sh'
  ':(exclude)proxmox/emby/NFS-incident-logs'
  ':(exclude)rancher/longhorn/migrations'
)
pattern="${old_name}|${old_name//_/-}"

if [[ "${1:-}" == "--dry-run" ]]; then
  git grep -n -I -E "$pattern" -- "${pathspec[@]}" || echo "No references left."
  exit 0
fi

mapfile -t files < <(git grep -l -I -E "$pattern" -- "${pathspec[@]}" || true)
if [[ ${#files[@]} -eq 0 ]]; then
  echo "No references left."
  exit 0
fi

sed -i -E "s/${old_name}/${new_name}/g; s/${old_name//_/-}/${new_name}/g" -- "${files[@]}"

printf 'Rewrote %d files:\n' "${#files[@]}"
git diff --stat -- "${files[@]}"
