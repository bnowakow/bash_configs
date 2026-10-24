#!/usr/bin/env bash
set -euo pipefail
app="${1:?Usage: migrate-one.sh profilarr|radarr}"
case "$app" in profilarr|radarr) claims=(config);; *) exit 2;; esac
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
k=(kubectl --kubeconfig "${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}")
ns="apps-$app"
job="$app-longhorn-20261024"
backup_dir=/tmp/longhorn-calibre-arr-originals
mkdir -p "$backup_dir"
deployment="$("${k[@]}" -n "$ns" get deployment "$app" -o json)"
printf '%s' "$deployment" | jq -e '.spec.replicas == 1' >/dev/null
printf '%s\n' "$deployment" > "$backup_dir/$app-source-deployment.json"
if "${k[@]}" -n "$ns" get job "$job" >/dev/null 2>&1; then
  echo "Job already exists; inspect before rerunning: $ns/$job" >&2
  exit 1
fi
for claim in "${claims[@]}"; do
  source="$app-$claim"
  target="$source-longhorn-rwo"
  printf '%s' "$deployment" | jq -e --arg source "$source" \
    'any(.spec.template.spec.volumes[]; .persistentVolumeClaim.claimName == $source)' >/dev/null
  "${k[@]}" -n "$ns" get pods -o json | jq -e --arg app "$app" --arg source "$source" '
    [.items[] | select(.status.phase != "Succeeded" and .status.phase != "Failed") |
      select(.metadata.labels["app.kubernetes.io/instance"] != $app) |
      select(any(.spec.volumes[]?; .persistentVolumeClaim.claimName == $source))] | length == 0
  ' >/dev/null
  "${k[@]}" -n "$ns" get pvc "$target" -o json | jq -e \
    '.status.phase == "Bound" and .spec.storageClassName == "longhorn-rwo-2replicas"' >/dev/null
  source_json="$("${k[@]}" -n "$ns" get pvc "$source" -o json)"
  printf '%s\n' "$source_json" > "$backup_dir/$source-source-pvc.json"
  pv="$(printf '%s' "$source_json" | jq -r '.spec.volumeName')"
  "${k[@]}" -n "$ns" annotate pvc "$source" helm.sh/resource-policy=keep --overwrite
  "${k[@]}" patch pv "$pv" --type=merge -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
done
stopped=0
cutover=0
# Invoked indirectly by the EXIT trap.
# shellcheck disable=SC2317
recover_copy_failure() {
  result=$?
  if [ "$result" -ne 0 ] && [ "$stopped" -eq 1 ] && [ "$cutover" -eq 0 ]; then
    echo "$app: copy failed; restoring the original replica count" >&2
    "${k[@]}" -n "$ns" scale deployment "$app" --replicas=1 || true
  fi
  exit "$result"
}
trap 'recover_copy_failure' EXIT
"${k[@]}" -n "$ns" scale deployment "$app" --replicas=0
stopped=1
shutdown_complete=0
for ((attempt=0; attempt<3; attempt++)); do
  if "${k[@]}" -n "$ns" wait --for=delete pod -l "app.kubernetes.io/instance=$app" --timeout=55s; then
    shutdown_complete=1
    break
  fi
done
[ "$shutdown_complete" -eq 1 ] || { echo "Shutdown incomplete; refusing copy" >&2; exit 1; }
"${k[@]}" create -f "$here/$app-copy-job.json"
copy_complete=0
for ((attempt=0; attempt<3; attempt++)); do
  if "${k[@]}" -n "$ns" wait --for=condition=complete "job/$job" --timeout=55s; then
    copy_complete=1
    break
  fi
  if "${k[@]}" -n "$ns" get job "$job" -o json | jq -e '(.status.failed // 0) > 0' >/dev/null; then
    "${k[@]}" -n "$ns" logs "job/$job" --all-containers=true || true
    break
  fi
done
[ "$copy_complete" -eq 1 ] || { echo "Copy/integrity checks incomplete; refusing cutover" >&2; exit 1; }
"${k[@]}" -n "$ns" logs "job/$job" --all-containers=true
cutover=1
cd "$root"
"$here/../pilot-2026-10-24/apply-bundle.sh" "$app" "rancher/fleet/apps/$app"
for ((attempt=0; attempt<60; attempt++)); do
  installed=1
  current="$("${k[@]}" -n "$ns" get deployment "$app" -o json)"
  for claim in "${claims[@]}"; do
    if ! printf '%s' "$current" | jq -e --arg target "$app-$claim-longhorn-rwo" \
      '.spec.replicas == 1 and any(.spec.template.spec.volumes[]; .persistentVolumeClaim.claimName == $target)' >/dev/null; then
      installed=0
    fi
  done
  # Profilarr's custom chart omits spec.replicas; restore only after new mount.
  if [ "$app" = profilarr ] && printf '%s' "$current" | jq -e --arg target "$app-config-longhorn-rwo" \
    'any(.spec.template.spec.volumes[]; .persistentVolumeClaim.claimName == $target)' >/dev/null; then
    "${k[@]}" -n "$ns" scale deployment "$app" --replicas=1
    installed=1
  fi
  if [ "$installed" -eq 1 ]; then
    for ((rollout=0; rollout<4; rollout++)); do
      if "${k[@]}" -n "$ns" rollout status "deployment/$app" --timeout=55s; then
        echo "$app: all target claims installed and deployment ready"
        exit 0
      fi
    done
    echo "Target installed but rollout incomplete; inspect before proceeding" >&2
    exit 1
  fi
  sleep 2
done
echo "Fleet has not installed all target claims; inspect before proceeding" >&2
exit 1
