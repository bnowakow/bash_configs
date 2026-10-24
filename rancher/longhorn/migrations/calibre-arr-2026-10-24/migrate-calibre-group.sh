#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
k=(kubectl --kubeconfig "${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}")
ns="apps-calibre"
apps=(calibre calibre-web kavita)
claims=(calibre-config calibre-library calibre-web-config kavita-config)
job=calibre-group-longhorn-20261024
backup=/tmp/longhorn-calibre-arr-originals
mkdir -p "$backup"
if "${k[@]}" -n "$ns" get job "$job" >/dev/null 2>&1; then
  echo "Copy Job already exists; inspect before rerunning" >&2
  exit 1
fi
for app in "${apps[@]}"; do
  current="$("${k[@]}" -n "$ns" get deployment "$app" -o json)"
  printf '%s' "$current" | jq -e --arg config "$app-config" '
    .spec.replicas == 1 and
    any(.spec.template.spec.volumes[]; .persistentVolumeClaim.claimName == $config) and
    any(.spec.template.spec.volumes[]; .persistentVolumeClaim.claimName == "calibre-library")' >/dev/null
  printf '%s\n' "$current" > "$backup/$app-source-deployment.json"
done
"${k[@]}" -n "$ns" get cronjob calibre-cover-maintenance -o json > "$backup/calibre-source-cronjob.json"
original_suspend="$(jq -r '.spec.suspend // false' "$backup/calibre-source-cronjob.json")"
# Reject maintenance or unknown live consumers before touching any writer.
"${k[@]}" -n "$ns" get pods -o json | jq -e '
  [.items[] | select(.status.phase != "Succeeded" and .status.phase != "Failed") |
   select(any(.spec.volumes[]?; .persistentVolumeClaim.claimName as $c |
     ["calibre-config","calibre-library","calibre-web-config","kavita-config"] | index($c))) |
   select(.metadata.labels["app.kubernetes.io/instance"] as $a |
     ["calibre","calibre-web","kavita"] | index($a) | not)] | length == 0' >/dev/null
for claim in "${claims[@]}"; do
  "${k[@]}" -n "$ns" get pvc "$claim-longhorn-rwo" -o json | jq -e \
    '.status.phase == "Bound" and .spec.storageClassName == "longhorn-rwo-2replicas"' >/dev/null
  "${k[@]}" -n "$ns" get pvc "$claim" -o json > "$backup/$claim-source-pvc.json"
  pv="$(jq -r '.spec.volumeName' "$backup/$claim-source-pvc.json")"
  "${k[@]}" -n "$ns" annotate pvc "$claim" helm.sh/resource-policy=keep --overwrite
  "${k[@]}" patch pv "$pv" --type=merge -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
done
stopped=0
suspended=0
cutover=0
# Invoked indirectly by the EXIT trap.
# shellcheck disable=SC2317
recover_pre_cutover() {
  result=$?
  if [ "$result" -ne 0 ] && [ "$cutover" -eq 0 ]; then
    if [ "$stopped" -eq 1 ]; then
      for app in "${apps[@]}"; do "${k[@]}" -n "$ns" scale deployment "$app" --replicas=1 || true; done
    fi
    if [ "$suspended" -eq 1 ]; then
      "${k[@]}" -n "$ns" patch cronjob calibre-cover-maintenance --type=merge -p "{\"spec\":{\"suspend\":$original_suspend}}" || true
    fi
  fi
  exit "$result"
}
trap 'recover_pre_cutover' EXIT
"${k[@]}" -n "$ns" patch cronjob calibre-cover-maintenance --type=merge -p '{"spec":{"suspend":true}}'
suspended=1
stopped=1
for app in "${apps[@]}"; do "${k[@]}" -n "$ns" scale deployment "$app" --replicas=0; done
for app in "${apps[@]}"; do
  gone=0
  for ((attempt=0; attempt<3; attempt++)); do
    if "${k[@]}" -n "$ns" wait --for=delete pod -l "app.kubernetes.io/instance=$app" --timeout=55s; then gone=1; break; fi
  done
  [ "$gone" -eq 1 ] || { echo "$app has not stopped; refusing copy" >&2; exit 1; }
done
# Closes the scheduling race: no source-volume consumer may still be alive.
"${k[@]}" -n "$ns" get pods -o json | jq -e '
 [.items[] | select(.status.phase != "Succeeded" and .status.phase != "Failed") |
  select(any(.spec.volumes[]?; .persistentVolumeClaim.claimName as $c |
    ["calibre-config","calibre-library","calibre-web-config","kavita-config"] | index($c)))] | length == 0' >/dev/null
"${k[@]}" create -f "$here/calibre-group-copy-job.json"
complete=0
for ((attempt=0; attempt<4; attempt++)); do
  if "${k[@]}" -n "$ns" wait --for=condition=complete "job/$job" --timeout=55s; then complete=1; break; fi
  if "${k[@]}" -n "$ns" get job "$job" -o json | jq -e '(.status.failed // 0) > 0' >/dev/null; then break; fi
done
"${k[@]}" -n "$ns" logs "job/$job"
[ "$complete" -eq 1 ] || { echo "Group copy/checks failed; refusing cutover" >&2; exit 1; }
cutover=1
cd "$root"
for app in "${apps[@]}"; do
  "$here/../pilot-2026-10-24/apply-bundle.sh" "$app" "rancher/fleet/apps/$app"
done
for app in "${apps[@]}"; do
  installed=0
  for ((attempt=0; attempt<60; attempt++)); do
    if "${k[@]}" -n "$ns" get deployment "$app" -o json | jq -e --arg config "$app-config-longhorn-rwo" '
      .spec.replicas == 1 and .spec.strategy.type == "Recreate" and
      .spec.template.spec.nodeSelector["kubernetes.io/hostname"] == "proxmox2-old" and
      any(.spec.template.spec.volumes[]; .persistentVolumeClaim.claimName == $config) and
      any(.spec.template.spec.volumes[]; .persistentVolumeClaim.claimName == "calibre-library-longhorn-rwo")' >/dev/null; then installed=1; break; fi
    sleep 2
  done
  [ "$installed" -eq 1 ] || { echo "$app target references not installed; inspect before proceeding" >&2; exit 1; }
  ready=0
  for ((attempt=0; attempt<4; attempt++)); do
    if "${k[@]}" -n "$ns" rollout status "deployment/$app" --timeout=55s; then ready=1; break; fi
  done
  [ "$ready" -eq 1 ] || { echo "$app target rollout incomplete; inspect before proceeding" >&2; exit 1; }
done
"$here/../pilot-2026-10-24/apply-bundle.sh" calibre-cover-maintenance rancher/fleet/apps/calibre-cover-maintenance
echo 'Calibre group ready; verify maintenance target references and final schedule state'
