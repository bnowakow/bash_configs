#!/usr/bin/env bash
set -Eeuo pipefail

remote_host=${K3S_CONFIG_HOST:-proxmox3.localdomain.bnowakowski.pl}
api_host=${K3S_API_HOST:-proxmox3.localdomain.bnowakowski.pl}
cert_host=${K3S_CERT_HOST:-proxmox3.tailscale.bnowakowski.pl}
output=${1:-/tmp/rancher-kubeconfig}
remote_path=/etc/rancher/k3s/k3s.yaml

die() { echo "ERROR: $*" >&2; exit 1; }

command -v scp >/dev/null || die "scp is required"
command -v sed >/dev/null || die "sed is required"

tmp_file=$(mktemp /tmp/k3s-kubeconfig.XXXXXX)
trap 'rm -f "$tmp_file"' EXIT

scp "${remote_host}:${remote_path}" "$tmp_file" || \
  die "could not copy ${remote_path} from ${remote_host}"

sed -i \
  -E "s#^([[:space:]]*server:)[[:space:]]+https://[^:]+:6443#\1 https://${api_host}:6443#" \
  "$tmp_file"

if grep -qE '^[[:space:]]*tls-server-name:' "$tmp_file"; then
  sed -i -E \
    "s#^([[:space:]]*tls-server-name:)[[:space:]]+.*#\1 ${cert_host}#" \
    "$tmp_file"
else
  sed -i \
    "/^[[:space:]]*server: https:\/\/${api_host}:6443$/a\\    tls-server-name: ${cert_host}" \
    "$tmp_file"
fi

grep -q "server: https://${api_host}:6443" "$tmp_file" || \
  die "the copied kubeconfig did not contain a server entry"
grep -q "tls-server-name: ${cert_host}" "$tmp_file" || \
  die "could not configure TLS server name"

install -m 600 "$tmp_file" "$output"
echo "K3s kubeconfig written to $output"
