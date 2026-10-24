#!/usr/bin/env bash
set -euo pipefail
app="${1:?Usage: migrate-one.sh openbooks|ubooquity}"
case "$app" in openbooks|ubooquity) ;; *) exit 2;; esac
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
k=(kubectl --kubeconfig "${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}")
ns="apps-$app"
if [ "$app" = openbooks ]; then
  sources=(openbooks-books openbooks-logs)
else
  sources=(ubooquity-config)
fi
targets_json="$(printf '%s\n' "${sources[@]}" | jq -R -s 'split("\n")[:-1] | map(. + "-longhorn-rwo")')"
sources_json="$(printf '%s\n' "${sources[@]}" | jq -R -s 'split("\n")[:-1]')"
job="$app-longhorn-20261024"
backup_dir=/tmp/longhorn-batch3-originals
mkdir -p "$backup_dir"
deployment="$("${k[@]}" -n "$ns" get deployment "$app" -o json)"
printf '%s' "$deployment" | jq -e --argjson sources "$sources_json" '
  . as $d | $d.spec.replicas == 1 and
  (($sources - [$d.spec.template.spec.volumes[] | .persistentVolumeClaim.claimName // empty]) | length == 0)
' >/dev/null
if "${k[@]}" -n "$ns" get job "$job" >/dev/null 2>&1; then
  echo "Job already exists; inspect before rerunning: $ns/$job" >&2
  exit 1
fi
printf '%s\n' "$deployment" > "$backup_dir/$app-source-deployment.json"
for source in "${sources[@]}"; do
  target="$source-longhorn-rwo"
  "${k[@]}" -n "$ns" get pvc "$target" -o json | jq -e \
    '.status.phase == "Bound" and .spec.storageClassName == "longhorn-rwo-2replicas"' >/dev/null
  source_json="$("${k[@]}" -n "$ns" get pvc "$source" -o json)"
  printf '%s\n' "$source_json" > "$backup_dir/$source-pvc.json"
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
"${k[@]}" -n "$ns" wait --for=condition=complete "job/$job" --timeout=55s
"${k[@]}" -n "$ns" logs "job/$job" --all-containers=true | tail -6
cutover=1
cd "$root"
"$here/../pilot-2026-10-24/apply-bundle.sh" "$app" "rancher/fleet/apps/$app"
# Rollout alone can succeed against the old scaled-to-zero deployment.
# Require the target mount and desired replica count to have arrived first.
for ((attempt=0; attempt<60; attempt++)); do
  if "${k[@]}" -n "$ns" get deployment "$app" -o json | jq -e --argjson targets "$targets_json" \
    '. as $d | $d.spec.replicas == 1 and (($targets - [$d.spec.template.spec.volumes[] | .persistentVolumeClaim.claimName // empty]) | length == 0)'  >/dev/null; then
    for ((rollout_attempt=0; rollout_attempt<3; rollout_attempt++)); do
      if "${k[@]}" -n "$ns" rollout status "deployment/$app" --timeout=55s; then
        echo "$app: migrated and running with all target Longhorn claims"
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
