#!/usr/bin/env bash

set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
playbook="$script_dir/site.yml"
inventory="$script_dir/inventory/hosts.ini"
vars_file="$script_dir/group_vars/all.yml"
env_file="${ANSIBLE_ENV_FILE:-$script_dir/.env}"
ask_become_pass=1
check_mode=0
syntax_check=0
list_hosts=0
extra_args=()

usage() {
  cat <<'USAGE'
Usage: ./run.sh [options] [-- ansible-playbook-options]

Runs the cluster bootstrap playbook using this repository's inventory and variables.

Options:
  -i, --inventory FILE       Inventory file (default: inventory/hosts.ini)
      --vars-file FILE       Extra variables YAML file
      --env-file FILE        Environment file (default: .env)
      --playbook FILE        Playbook (default: site.yml)
      --limit PATTERN        Limit execution to matching hosts/groups
      --tags TAGS             Run only tasks with these tags
      --skip-tags TAGS        Skip tasks with these tags
      --check                 Do not make changes
      --diff                  Show file differences
      --syntax-check          Check playbook syntax only
      --list-hosts            List matching hosts only
      --ask-become-pass       Prompt for the sudo/become password (default)
      --no-ask-become-pass    Do not prompt for the sudo/become password
  -h, --help                 Show this help

Anything after `--` is passed directly to ansible-playbook.
USAGE
}

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "Missing file: $path" >&2
    echo "Copy the example files first:" >&2
    echo "  cp '$script_dir/inventory/hosts.ini.example' '$inventory'" >&2
    echo "  cp '$script_dir/group_vars/all.yml.example' '$vars_file'" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--inventory)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 2; }
      inventory="$2"
      [[ "$inventory" = /* ]] || inventory="$script_dir/$inventory"
      shift 2
      ;;
    --vars-file)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 2; }
      vars_file="$2"
      [[ "$vars_file" = /* ]] || vars_file="$script_dir/$vars_file"
      shift 2
      ;;
    --env-file)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 2; }
      env_file="$2"
      [[ "$env_file" = /* ]] || env_file="$script_dir/$env_file"
      shift 2
      ;;
    --playbook)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 2; }
      playbook="$2"
      [[ "$playbook" = /* ]] || playbook="$script_dir/$playbook"
      shift 2
      ;;
    --limit|--tags|--skip-tags)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 2; }
      extra_args+=("$1" "$2")
      shift 2
      ;;
    --check|--diff)
      extra_args+=("$1")
      [[ "$1" == "--check" ]] && check_mode=1
      shift
      ;;
    --syntax-check)
      extra_args+=("$1")
      syntax_check=1
      shift
      ;;
    --list-hosts)
      extra_args+=("$1")
      list_hosts=1
      shift
      ;;
    --ask-become-pass)
      ask_become_pass=1
      shift
      ;;
    --no-ask-become-pass)
      ask_become_pass=0
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      extra_args+=("$@")
      break
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

command -v ansible-playbook >/dev/null 2>&1 || {
  echo "ansible-playbook is not installed or is not in PATH." >&2
  exit 2
}

require_file "$inventory"
require_file "$vars_file"

if [[ -f "$env_file" ]]; then
  # The file is local operator-controlled shell syntax and is never printed.
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
fi

playbook_args=(
  --inventory "$inventory"
  --extra-vars "@$vars_file"
  "${extra_args[@]}"
  "$playbook"
)

if [[ "$ask_become_pass" -eq 1 ]]; then
  playbook_args+=(--ask-become-pass)
fi

if ansible-playbook "${playbook_args[@]}"; then
  :
else
  playbook_rc=$?
  exit "$playbook_rc"
fi

# A normal bootstrap is not complete until Fleet's storage and backup agents are
# healthy. Do not run this after dry-run, syntax-check, host-list, or another playbook.
if [[ "$playbook" == "$script_dir/site.yml" && "$check_mode" -eq 0 && "$syntax_check" -eq 0 && "$list_hosts" -eq 0 ]]; then
  verification_args=(
    --inventory "$inventory"
    --extra-vars "@$vars_file"
    "$script_dir/verify.yml"
  )

  if [[ "$ask_become_pass" -eq 1 ]]; then
    verification_args+=(--ask-become-pass)
  fi

  ansible-playbook "${verification_args[@]}"
fi
