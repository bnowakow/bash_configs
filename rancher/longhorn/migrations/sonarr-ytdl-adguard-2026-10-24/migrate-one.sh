#!/usr/bin/env bash
set -euo pipefail
app="${1:?Usage: migrate-one.sh sonarr|youtubedl-material|adguard-home}"
case "$app" in
 sonarr) claims=(sonarr-config); workloads=(sonarr);;
 youtubedl-material) claims=(youtubedl-material-appdata youtubedl-material-users youtubedl-material-mongodb-data); workloads=(youtubedl-material youtubedl-material-mongodb);;
 adguard-home) claims=(adguard-home-config adguard-home-data); workloads=(adguard-home);;
 *) exit 2;;
esac
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
k=(kubectl --kubeconfig "${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}")
ns="apps-$app"
job="$app-longhorn-20261024"
backup=/tmp/longhorn-sonarr-ytdl-adguard-originals
mkdir -p "$backup"
"${k[@]}" --request-timeout=15s get --raw=/readyz >/dev/null
python3 - "$root" "$backup" "$app" <<'PY'
import json,sys,pathlib
root,backup,app=map(pathlib.Path,sys.argv[1:])
original=json.loads((backup/'repository-files.json').read_text())
for f in ('fleet.yaml','values.yaml'):
 name='fleet/apps/'+str(app)+'/'+f
 assert (root/name).read_text()==original[name], 'App definitions changed since preflight; inspect before overwriting'
PY
if "${k[@]}" -n "$ns" get job "$job" >/dev/null 2>&1; then
 echo 'Copy Job already exists; inspect before rerunning' >&2; exit 1
fi
selectors=()
for workload in "${workloads[@]}"; do
 current="$("${k[@]}" -n "$ns" get deployment "$workload" -o json)"
 printf '%s' "$current" | jq -e '.spec.replicas == 1 and .status.availableReplicas == 1' >/dev/null
 printf '%s\n' "$current" > "$backup/$workload-source-deployment.json"
 selectors+=("$(printf '%s' "$current" | jq -r '.spec.selector.matchLabels|to_entries|map("\(.key)=\(.value)")|join(",")')")
done
for claim in "${claims[@]}"; do
 found=0
 for workload in "${workloads[@]}"; do
  if jq -e --arg claim "$claim" 'any(.spec.template.spec.volumes[]; .persistentVolumeClaim.claimName == $claim)' "$backup/$workload-source-deployment.json" >/dev/null; then found=1; fi
 done
 [ "$found" -eq 1 ] || { echo "Source $claim not in expected workloads" >&2; exit 1; }
 "${k[@]}" -n "$ns" get pods -o json | jq -e --arg app "$app" --arg source "$claim" '
 [.items[]|select(.status.phase!="Succeeded" and .status.phase!="Failed")|
 select(.metadata.labels["app.kubernetes.io/instance"]!=$app)|
 select(any(.spec.volumes[]?;.persistentVolumeClaim.claimName==$source))]|length==0' >/dev/null
 "${k[@]}" -n "$ns" get pods -o json | jq -e --arg target "$claim-longhorn-rwo" '
 [.items[]|select(.status.phase!="Succeeded" and .status.phase!="Failed")|
 select(any(.spec.volumes[]?;.persistentVolumeClaim.claimName==$target))]|length==0' >/dev/null
 "${k[@]}" -n "$ns" get pvc "$claim-longhorn-rwo" -o json | jq -e '.status.phase=="Bound" and .spec.storageClassName=="longhorn-rwo-2replicas"' >/dev/null
 "${k[@]}" -n "$ns" get pvc "$claim" -o json > "$backup/$claim-source-pvc.json"
 pv="$(jq -r '.spec.volumeName' "$backup/$claim-source-pvc.json")"
 "${k[@]}" -n "$ns" annotate pvc "$claim" helm.sh/resource-policy=keep --overwrite
 "${k[@]}" patch pv "$pv" --type=merge -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
done
stopped=0
cutover=0
# Called indirectly by EXIT.
# shellcheck disable=SC2317
recover_pre_cutover() {
 result=$?
 if [ "$result" -ne 0 ] && [ "$stopped" -eq 1 ] && [ "$cutover" -eq 0 ]; then
  echo 'Pre-cutover failure: restoring source writers, database before app' >&2
  for ((i=${#workloads[@]}-1; i>=0; i--)); do
   "${k[@]}" -n "$ns" scale deployment "${workloads[i]}" --replicas=1 || true
   "${k[@]}" -n "$ns" rollout status "deployment/${workloads[i]}" --timeout=55s || true
  done
 fi
 exit "$result"
}
trap 'recover_pre_cutover' EXIT
stopped=1
# App first, database second. Do not wait on the shared release selector.
for i in "${!workloads[@]}"; do
 "${k[@]}" -n "$ns" scale deployment "${workloads[i]}" --replicas=0
 gone=0
 for ((attempt=0;attempt<4;attempt++)); do
  if "${k[@]}" -n "$ns" wait --for=delete pod -l "${selectors[i]}" --timeout=55s; then gone=1; break; fi
 done
 [ "$gone" -eq 1 ] || { echo 'Shutdown incomplete; refusing copy' >&2; exit 1; }
done
if [ "$app" = adguard-home ]; then
 # This persistent probe was started and checked before DNS downtime.
 "${k[@]}" -n "$ns" exec adguard-cluster-dns-probe-20261024 -- python -c \
  'import socket; [print(h,socket.gethostbyname(h)) for h in ("nas.localdomain.bnowakowski.pl.","oci.trueforge.org.")]'
fi
"${k[@]}" create -f "$here/$app-copy-job.json"
complete=0
for ((attempt=0;attempt<8;attempt++)); do
 if "${k[@]}" -n "$ns" wait --for=condition=complete "job/$job" --timeout=55s; then complete=1; break; fi
 if "${k[@]}" -n "$ns" get job "$job" -o json | jq -e '(.status.failed//0)>0' >/dev/null; then break; fi
done
"${k[@]}" -n "$ns" logs "job/$job" --all-containers=true
[ "$complete" -eq 1 ] || { echo 'Copy/engine checks incomplete; refusing cutover' >&2; exit 1; }
for claim in "${claims[@]}"; do
 "${k[@]}" -n "$ns" get pods -o json | jq -e --arg source "$claim" '
 [.items[]|select(.status.phase!="Succeeded" and .status.phase!="Failed")|
 select(any(.spec.volumes[]?;.persistentVolumeClaim.claimName==$source))]|length==0' >/dev/null
done
"${k[@]}" --request-timeout=15s get --raw=/readyz >/dev/null
cutover=1
# Only materialize active target references after all stopped-copy checks pass.
python3 - "$root" "$here" "$app" <<'PY'
import json,pathlib,sys
root,here,app=map(pathlib.Path,sys.argv[1:]);prepared=json.loads((here/'prepared-fleet-files.json').read_text())
for f in ('fleet.yaml','values.yaml'):
 name='fleet/apps/'+str(app)+'/'+f; text=prepared[name]
 if str(app)=='youtubedl-material' and f=='values.yaml':text=text.replace('workload:\n  main:\n    replicas: 1','workload:\n  main:\n    replicas: 0',1)
 (root/name).write_text(text)
PY
apply_bundle() {
 cd "$root"
 "$here/../pilot-2026-10-24/apply-bundle.sh" "$app" "rancher/fleet/apps/$app"
}
wait_target() {
 local workload="$1" desired="$2" arrived=0
 for ((attempt=0;attempt<90;attempt++)); do
  current="$("${k[@]}" -n "$ns" get deployment "$workload" -o json)"
  if printf '%s' "$current" | jq -e --argjson desired "$desired" '
    .spec.replicas==$desired and .spec.strategy.type=="Recreate" and
    ([.spec.template.spec.volumes[]|select(.persistentVolumeClaim)|.persistentVolumeClaim.claimName|endswith("-longhorn-rwo")]|all)' >/dev/null; then arrived=1; break; fi
  sleep 2
 done
 [ "$arrived" -eq 1 ] || { echo 'Target mounts/replicas did not arrive; inspect before proceeding' >&2; return 1; }
 if [ "$desired" -eq 1 ]; then
  for ((attempt=0;attempt<5;attempt++)); do
   if "${k[@]}" -n "$ns" rollout status "deployment/$workload" --timeout=55s; then return 0; fi
  done
  return 1
 fi
}
apply_bundle
if [ "$app" = youtubedl-material ]; then
 wait_target youtubedl-material 0
 wait_target youtubedl-material-mongodb 1
 python3 - "$root" "$here" <<'PY'
import pathlib,json,sys
root,here=map(pathlib.Path,sys.argv[1:]);name='fleet/apps/youtubedl-material/values.yaml'
(root/name).write_text(json.loads((here/'prepared-fleet-files.json').read_text())[name])
PY
 apply_bundle
fi
wait_target "$app" 1
echo "$app: migrated with checked target state and one ready instance"
