#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
namespace="${1:?Usage: verify-homer-restore.sh NAMESPACE POD CONTAINER CHECKSUM_FILE}"
pod="${2:?Missing pod}"
container="${3:?Missing container}"
checksums="${4:?Missing source checksums}"
kubectl -n "$namespace" get pvc,pods -o wide
kubectl -n "$namespace" exec -i "$pod" -c "$container" -- sh -c \
  'cd /www/assets && sha256sum -c -' < "$checksums"
kubectl -n "$namespace" exec "$pod" -c "$container" -- sh -c \
  'wget -q -O /dev/null http://127.0.0.1:8080/ && wget -q -O /dev/null http://127.0.0.1:8080/assets/config.yml'
echo 'All source checksums match; Homer serves the dashboard and configuration.'
