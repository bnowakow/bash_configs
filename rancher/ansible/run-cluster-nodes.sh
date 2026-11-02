#!/usr/bin/env bash
# Apply site.yml host configuration to the nodes of the running k3s cluster
# (inventory/k3s-cluster.ini: proxmox3 and proxmox2-old).
#
# Unlike run.sh (a full cluster bootstrap), this only runs the plays that are
# safe on a live cluster:
#   host-prep       packages, iscsid, dm_crypt, sysctl (bridge-nf-call-iptables)
#   longhorn-disks  find and mount the Longhorn filesystem (formatting is off)
# The k3s plays always restart k3s and can upgrade it to k3s_version, and the
# bootstrap play reinstalls Rancher/Fleet, so they are refused here unless
# --allow-cluster-changes is given.
#
# Examples:
#   ./run-cluster-nodes.sh --check --diff        # preview, changes nothing
#   ./run-cluster-nodes.sh                        # apply to both nodes
#   ./run-cluster-nodes.sh --limit proxmox2-old   # one node
#   ./run-cluster-nodes.sh --become-password-file ../../tmp-sudo-password

set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
inventory="$script_dir/inventory/k3s-cluster.ini"
vars_file="$script_dir/group_vars/all.yml"
playbook="$script_dir/site.yml"
tags="host-prep,longhorn-disks"
allow_cluster_changes=0
become_password_file=""
extra_args=()

usage() {
  cat <<'USAGE'
Usage: ./run-cluster-nodes.sh [options] [-- ansible-playbook-options]

Runs site.yml host configuration against the k3s cluster nodes only.

Options:
      --tags TAGS                  Plays to run (default: host-prep,longhorn-disks)
      --limit PATTERN              Only these nodes, e.g. proxmox3
      --check                      Dry run, change nothing
      --diff                       Show file differences
      --become-password-file FILE  Read the sudo password from FILE instead of
                                   prompting (same password on both nodes)
      --allow-cluster-changes      Permit the k3s and bootstrap tags (restarts or
                                   upgrades k3s, reinstalls Rancher/Fleet)
  -h, --help                       Show this help

Anything after `--` is passed directly to ansible-playbook.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tags|--limit)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 2; }
      if [[ "$1" == "--tags" ]]; then tags="$2"; else extra_args+=(--limit "$2"); fi
      shift 2
      ;;
    --become-password-file)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 2; }
      become_password_file="$2"
      shift 2
      ;;
    --check|--diff)
      extra_args+=("$1")
      shift
      ;;
    --allow-cluster-changes)
      allow_cluster_changes=1
      shift
      ;;
    -h|--help)
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

for f in "$inventory" "$vars_file" "$playbook"; do
  [[ -f "$f" ]] || { echo "Missing file: $f" >&2; exit 2; }
done

IFS=',' read -r -a tag_list <<< "$tags"
for tag in "${tag_list[@]}"; do
  case "$tag" in
    host-prep|longhorn-disks) ;;
    k3s|bootstrap|all)
      if [[ "$allow_cluster_changes" -ne 1 ]]; then
        echo "Tag '$tag' restarts/upgrades k3s or reinstalls Rancher on the live cluster." >&2
        echo "Re-run with --allow-cluster-changes if that is really intended." >&2
        exit 2
      fi
      ;;
    *)
      echo "Unknown tag: $tag (known: host-prep, longhorn-disks, k3s, bootstrap)" >&2
      exit 2
      ;;
  esac
done

playbook_args=(
  --inventory "$inventory"
  --extra-vars "@$vars_file"
  --tags "$tags"
)

if [[ -n "$become_password_file" ]]; then
  [[ -r "$become_password_file" ]] || { echo "Cannot read $become_password_file" >&2; exit 2; }
  playbook_args+=(--become-password-file "$become_password_file")
else
  playbook_args+=(--ask-become-pass)
fi

if ! "$script_dir/sync-k3s-inventory.sh" --check >/dev/null 2>&1; then
  echo "Warning: $inventory does not match the live k3s nodes (or the check failed)." >&2
  echo "         Run ./sync-k3s-inventory.sh to see the difference and update it." >&2
fi

echo "Inventory: $inventory"
echo "Tags:      $tags"
exec ansible-playbook "${playbook_args[@]}" "${extra_args[@]}" "$playbook"
