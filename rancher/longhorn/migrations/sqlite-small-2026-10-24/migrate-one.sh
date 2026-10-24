#!/usr/bin/env bash
set -euo pipefail
app="${1:?Usage: migrate-one.sh jellyseerr|cleanuparr|uptime-kuma}"
case "$app" in jellyseerr|cleanuparr|uptime-kuma) ;; *) exit 2;; esac
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
k=(kubectl --kubeconfig "${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}")
ns="apps-$app"
source="$app-config"
target="$source-longhorn-rwo"
job="$app-sqlite-longhorn-20261024"
backup_dir=/tmp/longhorn-sqlite-small-originals
mkdir -p "$backup_dir"
source_json="$("${k[@]}" -n "$ns" get pvc "$source" -o json)"
deployment="$("${k[@]}" -n "$ns" get deployment "$app" -o json)"
printf '%s' "$deployment" | jq -e --arg source "$source" \
  '.spec.replicas == 1 and any(.spec.template.spec.volumes[]; .persistentVolumeClaim.claimName == $source)' >/dev/null
"${k[@]}" -n "$ns" get pods -o json | jq -e --arg app "$app" --arg source "$source" '
  [.items[] | select(.status.phase != "Succeeded" and .status.phase != "Failed") |
    select(.metadata.labels["app.kubernetes.io/instance"] != $app) |
    select(any(.spec.volumes[]?; .persistentVolumeClaim.claimName == $source))] | length == 0
' >/dev/null
"${k[@]}" -n "$ns" get pvc "$target" -o json | jq -e \
  '.status.phase == "Bound" and .spec.storageClassName == "longhorn-rwo-2replicas"' >/dev/null
if "${k[@]}" -n "$ns" get job "$job" >/dev/null 2>&1; then
  echo "Job already exists; inspect before rerunning: $ns/$job" >&2
  exit 1
fi
printf '%s\n' "$source_json" > "$backup_dir/$app-source-pvc.json"
printf '%s\n' "$deployment" > "$backup_dir/$app-source-deployment.json"
pv="$(printf '%s' "$source_json" | jq -r '.spec.volumeName')"
"${k[@]}" -n "$ns" annotate pvc "$source" helm.sh/resource-policy=keep --overwrite
"${k[@]}" patch pv "$pv" --type=merge -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
stopped=0
cutover=0
# Invoked indirectly by the EXIT trap.
# shellcheck disable=SC2317
recover_copy_failure() {
  result=$?
  if [ "$result" -ne 0 ] && [ "$stopped" -eq 1 ] && [ "$cutover" -eq 0 ]; then
    echo "$app: copy failed; restoring the original deployment replica count" >&2
    "${k[@]}" -n "$ns" scale deployment "$app" --replicas=1 || true
  fi
  exit "$result"
}
trap 'recover_copy_failure' EXIT
"${k[@]}" -n "$ns" scale deployment "$app" --replicas=0
stopped=1
# Never copy after a failed shutdown wait: the old process might still write.
shutdown_complete=0
for ((shutdown_attempt=0; shutdown_attempt<3; shutdown_attempt++)); do
  if "${k[@]}" -n "$ns" wait --for=delete pod -l "app.kubernetes.io/instance=$app" --timeout=55s; then
    shutdown_complete=1
    break
  fi
  echo "$app: still waiting for graceful shutdown"
done
[ "$shutdown_complete" -eq 1 ] || { echo "$app: shutdown did not finish; refusing to copy" >&2; exit 1; }
"${k[@]}" apply -f "$here/$app-copy-job.json"
copy_complete=0
for ((copy_attempt=0; copy_attempt<3; copy_attempt++)); do
  if "${k[@]}" -n "$ns" wait --for=condition=complete "job/$job" --timeout=55s; then
    copy_complete=1
    break
  fi
  if "${k[@]}" -n "$ns" get job "$job" -o json | jq -e '(.status.failed // 0) > 0' >/dev/null; then
    "${k[@]}" -n "$ns" logs "job/$job" || true
    break
  fi
done
[ "$copy_complete" -eq 1 ] || { echo "$app: SQLite/copy checks did not complete; refusing cutover" >&2; exit 1; }
"${k[@]}" -n "$ns" logs "job/$job"
cutover=1
cd "$root"
"$here/../pilot-2026-10-24/apply-bundle.sh" "$app" "rancher/fleet/apps/$app"
# Rollout alone can succeed against the old scaled-to-zero deployment.
# Require the target mount and desired replica count to have arrived first.
for ((attempt=0; attempt<60; attempt++)); do
  if "${k[@]}" -n "$ns" get deployment "$app" -o json | jq -e --arg target "$target" \
    'any(.spec.template.spec.volumes[]; .persistentVolumeClaim.claimName == $target)' >/dev/null; then
    # Cleanuparr's chart omits spec.replicas: restore the single replica only
    # after its new mount is installed, never while the old DB could be used.
    if [ "$app" = cleanuparr ]; then
      "${k[@]}" -n "$ns" scale deployment "$app" --replicas=1
    fi
    "${k[@]}" -n "$ns" get deployment "$app" -o json | jq -e '.spec.replicas == 1' >/dev/null
    for ((rollout_attempt=0; rollout_attempt<3; rollout_attempt++)); do
      if "${k[@]}" -n "$ns" rollout status "deployment/$app" --timeout=55s; then
        echo "$app: migrated and running with $target"
        exit 0
      fi
      echo "$app: waiting for storage attachment and application readiness"
    done
    echo "$app: target mounted but rollout did not finish; inspect before proceeding" >&2
    exit 1
  fi
  sleep 2
done
echo "$app: Fleet has not installed the target mount; inspect before proceeding" >&2
exit 1
