#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
k=(kubectl --kubeconfig "${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}")
ns=apps-filebot
mkdir -p /tmp/longhorn-filebot-originals
"${k[@]}" -n "$ns" get deployment filebot -o json | jq -e '.spec.replicas == 0' >/dev/null
# A disabled Deployment alone does not exclude a backup/maintenance writer.
"${k[@]}" -n "$ns" get pods -o json | jq -e '
  [.items[] | select(.status.phase != "Succeeded" and .status.phase != "Failed") |
    select(any(.spec.volumes[]?; (.persistentVolumeClaim.claimName // "") |
      test("^filebot-(config|output|watch)$")))] | length == 0
' >/dev/null
if "${k[@]}" -n "$ns" get job filebot-longhorn-20261024 >/dev/null 2>&1; then
  echo 'Migration job already exists; inspect before rerunning' >&2
  exit 1
fi
for key in config output watch; do
  source="filebot-$key"
  target="$source-longhorn-rwo"
  "${k[@]}" -n "$ns" get pvc "$target" -o json | jq -e \
    '.status.phase == "Bound" and .spec.storageClassName == "longhorn-rwo-2replicas"' >/dev/null
  source_json="$("${k[@]}" -n "$ns" get pvc "$source" -o json)"
  printf '%s\n' "$source_json" > "/tmp/longhorn-filebot-originals/$source-pvc.json"
  pv="$(printf '%s' "$source_json" | jq -r '.spec.volumeName')"
  "${k[@]}" -n "$ns" annotate pvc "$source" helm.sh/resource-policy=keep --overwrite
  "${k[@]}" patch pv "$pv" --type=merge -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
done
"${k[@]}" apply -f "$here/copy-job.json"
copy_complete=0
for ((attempt=0; attempt<3; attempt++)); do
  if "${k[@]}" -n "$ns" wait --for=condition=complete job/filebot-longhorn-20261024 --timeout=55s; then
    copy_complete=1
    break
  fi
  if "${k[@]}" -n "$ns" get job filebot-longhorn-20261024 -o json | jq -e '(.status.failed // 0) > 0' >/dev/null; then break; fi
done
[ "$copy_complete" -eq 1 ] || { echo 'Copy not verified; refusing cutover' >&2; exit 1; }
"${k[@]}" -n "$ns" logs job/filebot-longhorn-20261024 --all-containers=true | tail -8
cd "$root"
"$here/../pilot-2026-10-24/apply-bundle.sh" filebot rancher/fleet/apps/filebot
for ((attempt=0; attempt<60; attempt++)); do
  if "${k[@]}" -n "$ns" get deployment filebot -o json | jq -e '
    .spec.replicas == 0 and any(.spec.template.spec.volumes[];
      .persistentVolumeClaim.claimName == "filebot-config-longhorn-rwo")
  ' >/dev/null; then
    echo 'Filebot target config installed; application remains scaled to zero'
    exit 0
  fi
  sleep 2
done
echo 'Fleet has not installed target config; inspect before proceeding' >&2
exit 1
