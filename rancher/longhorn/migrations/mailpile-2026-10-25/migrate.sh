#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
k=(kubectl --kubeconfig "${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}")
backup=/tmp/longhorn-mailpile-originals
ns="apps-mailpile"
claims=(mailpile-path1 mailpile-path2)
"${k[@]}" --request-timeout=15s get --raw=/readyz >/dev/null
"${k[@]}" -n "$ns" get deployment mailpile -o json > "$backup/source-deployment.json"
jq -e '.spec.replicas==1 and .status.availableReplicas==1' "$backup/source-deployment.json" >/dev/null
selector="$(jq -r '.spec.selector.matchLabels|to_entries|map("\(.key)=\(.value)")|join(",")' "$backup/source-deployment.json")"
if "${k[@]}" -n "$ns" get job mailpile-longhorn-copy-20261025 >/dev/null 2>&1; then
 echo 'Copy Job already exists; inspect before rerunning' >&2; exit 1
fi
for claim in "${claims[@]}"; do
 jq -e --arg claim "$claim" 'any(.spec.template.spec.volumes[];.persistentVolumeClaim.claimName==$claim)' "$backup/source-deployment.json" >/dev/null
 "${k[@]}" -n "$ns" get pods -o json | jq -e --arg source "$claim" '
 [.items[]|select(.status.phase!="Succeeded" and .status.phase!="Failed")|
 select(.metadata.labels["app.kubernetes.io/instance"]!="mailpile")|
 select(any(.spec.volumes[]?;.persistentVolumeClaim.claimName==$source))]|length==0' >/dev/null
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
recover_failure() {
 result=$?
 if [ "$result" -ne 0 ] && [ "$stopped" -eq 1 ] && [ "$cutover" -eq 0 ]; then
  echo 'Pre-cutover failure; restoring Mailpile on its original claims' >&2
  "${k[@]}" -n "$ns" scale deployment mailpile --replicas=1 || true
 fi
 exit "$result"
}
trap 'recover_failure' EXIT
stopped=1
"${k[@]}" -n "$ns" scale deployment mailpile --replicas=0
gone=0
for ((i=0;i<5;i++)); do
 if "${k[@]}" -n "$ns" wait --for=delete pod -l "$selector" --timeout=55s; then gone=1; break; fi
done
[ "$gone" -eq 1 ] || { echo 'Source writer did not stop; refusing copy' >&2; exit 1; }
"${k[@]}" create -f "$here/copy-job.json"
wait_job() {
 local namespace="$1" job="$2" done=0
 for ((attempt=0;attempt<30;attempt++)); do
  if "${k[@]}" -n "$namespace" wait --for=condition=complete "job/$job" --timeout=55s; then done=1; break; fi
  if "${k[@]}" -n "$namespace" get job "$job" -o json | jq -e '(.status.failed//0)>0' >/dev/null; then break; fi
 done
 "${k[@]}" -n "$namespace" logs "job/$job" --all-containers=true
 [ "$done" -eq 1 ] || { echo "$job did not pass; refusing cutover" >&2; return 1; }
}
wait_job "$ns" mailpile-longhorn-copy-20261025
"${k[@]}" create -f /tmp/mailpile-backup-holder.json
"${k[@]}" -n "$ns" wait --for=condition=Ready pod/mailpile-backup-holder-20261025 --timeout=55s
"${k[@]}" -n longhorn-system create job --from=cronjob/nas-daily-backup mailpile-nas-backup-20261025
wait_job longhorn-system mailpile-nas-backup-20261025
"${k[@]}" -n longhorn-system get job mailpile-nas-backup-20261025 -o json > /tmp/mailpile-backup-job.json
"${k[@]}" -n longhorn-system get backups.longhorn.io -o json > /tmp/mailpile-backups.json
"${k[@]}" -n "$ns" get pvc -o json > /tmp/mailpile-backup-pvcs.json
python3 "$here/prepare-restore.py"
"${k[@]}" create -f /tmp/mailpile-isolated-restore.json
wait_job "$ns" mailpile-isolated-restore-20261025
"${k[@]}" --request-timeout=15s get --raw=/readyz >/dev/null
# Evidence checksum is safe to log; the private per-file manifest stays on scratch.
"${k[@]}" -n "$ns" exec mailpile-backup-holder-20261025 -- python -c \
 'import hashlib;print("Stopped-copy manifest SHA256:",hashlib.sha256(open("/evidence/manifest.json","rb").read()).hexdigest())'
"${k[@]}" -n "$ns" delete pod mailpile-backup-holder-20261025
cutover=1
python3 - "$root" "$here" <<'PY'
import json,pathlib,sys
root,here=map(pathlib.Path,sys.argv[1:]);prepared=json.loads((here/'prepared-fleet-files.json').read_text())
for name,text in prepared.items():(root/name).write_text(text)
PY
cd "$root"
"$here/../pilot-2026-10-24/apply-bundle.sh" mailpile rancher/fleet/apps/mailpile
arrived=0
for ((i=0;i<90;i++)); do
 if "${k[@]}" -n "$ns" get deployment mailpile -o json | jq -e '
 .spec.replicas==1 and .spec.strategy.type=="Recreate" and
 any(.spec.template.spec.volumes[];.persistentVolumeClaim.claimName=="mailpile-path1-longhorn-rwo") and
 any(.spec.template.spec.volumes[];.persistentVolumeClaim.claimName=="mailpile-path2-longhorn-rwo")' >/dev/null; then arrived=1; break; fi
 sleep 2
done
[ "$arrived" -eq 1 ] || { echo 'Target references did not arrive; inspect before proceeding' >&2; exit 1; }
for ((i=0;i<10;i++)); do
 if "${k[@]}" -n "$ns" rollout status deployment/mailpile --timeout=55s; then
  echo 'Mailpile ready on verified/restored Longhorn state; original claims retained'
  exit 0
 fi
done
echo 'Target rollout incomplete; inspect before changing data copies' >&2
exit 1
