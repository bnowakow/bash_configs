#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
kubeconfig="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
bundle="${1:?Usage: apply-bundle.sh BUNDLE REPOSITORY_RELATIVE_PATH}"
bundle_path="${2:?Missing bundle path}"
k=(kubectl --kubeconfig "$kubeconfig")
labels=()
# Native Fleet apply refreshes the values Secret. Use a single-bundle prune
# scope and preserve GitRepo ownership instead of pruning the GitRepo scope.
others="$("${k[@]}" -n fleet-local get bundles -l "fleet.cattle.io/repo-name=$bundle" -o json | jq -r --arg bundle "$bundle" '.items[] | select(.metadata.name != $bundle) | .metadata.name')"
[ -z "$others" ] || { echo "Unsafe prune scope: $others" >&2; exit 1; }
if current="$("${k[@]}" -n fleet-local get bundle "$bundle" -o json 2>/dev/null)"; then
  mkdir -p /tmp/longhorn-pilot-originals
  [ -e "/tmp/longhorn-pilot-originals/bundle-$bundle.json" ] || printf '%s\n' "$current" > "/tmp/longhorn-pilot-originals/bundle-$bundle.json"
  while IFS= read -r label; do labels+=(--label "$label"); done < <(printf '%s' "$current" | jq -r '.metadata.labels // {} | to_entries[] | select(.key != "fleet.cattle.io/commit") | "\(.key)=\(.value)"')
else
  labels+=(--label fleet.cattle.io/repo-name=rancher-cluster)
fi
cd "$root"
fleet apply --kubeconfig "$kubeconfig" --namespace fleet-local "${labels[@]}" "$bundle" "$bundle_path"
