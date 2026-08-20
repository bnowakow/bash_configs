#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubeconfig_path="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
namespace="apps-adguard-home"
release="adguard-home"
deployment="adguard-home"
chart_ref="oci://oci.trueforge.org/truecharts/adguard-home"
chart_version="${ADGUARD_CHART_VERSION:-13.7.0}"
job_name="adguard-home-longhorn-migration"
yes_mode=0
dry_run=0
phase="all"

usage() {
  cat <<EOF
Usage: $0 [--phase all|prepare|copy|cutover] [--yes] [--dry-run]

Phases:
  prepare   Create the two Longhorn PVCs and wait for them to bind.
  copy      Stop AdGuard and copy both local-path PVCs to Longhorn.
  cutover   Upgrade the Helm release to use the Longhorn PVCs.
  all       Run prepare, copy, and cutover (default).

--yes       Required for phases that stop AdGuard or perform the cutover.
--dry-run   Server-side dry-run Kubernetes changes; never stop or upgrade.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --phase)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      phase="$2"
      shift 2
      ;;
    --yes) yes_mode=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$phase" in
  all|prepare|copy|cutover) ;;
  *) echo "Invalid phase: $phase" >&2; exit 2 ;;
esac

for command in kubectl helm; do
  command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 2; }
done

kubectl_cmd=(kubectl --kubeconfig "$kubeconfig_path")
helm_cmd=(helm --kubeconfig "$kubeconfig_path")
pvc_manifest="$script_dir/pvc.yaml"
job_manifest="$script_dir/copy-job.yaml"

require_confirmation() {
  if [ "$yes_mode" -ne 1 ]; then
    echo "This phase changes cluster state. Re-run with --yes to continue: $*" >&2
    exit 2
  fi
}

run_prepare() {
  if [ "$dry_run" -eq 1 ]; then
    "${kubectl_cmd[@]}" apply --dry-run=server -f "$pvc_manifest"
    return
  fi
  "${kubectl_cmd[@]}" apply -f "$pvc_manifest"
  "${kubectl_cmd[@]}" -n "$namespace" wait --for=jsonpath='{.status.phase}'=Bound \
    pvc/adguard-home-config-longhorn pvc/adguard-home-data-longhorn --timeout=10m
}

run_copy() {
  require_confirmation "--phase copy"
  if [ "$dry_run" -eq 1 ]; then
    "${kubectl_cmd[@]}" apply --dry-run=server -f "$job_manifest"
    return
  fi
  if "${kubectl_cmd[@]}" -n "$namespace" get job "$job_name" >/dev/null 2>&1; then
    echo "Job $namespace/$job_name already exists; inspect it before rerunning." >&2
    exit 1
  fi
  "${kubectl_cmd[@]}" -n "$namespace" scale deployment "$deployment" --replicas=0
  "${kubectl_cmd[@]}" -n "$namespace" wait --for=delete \
    pod -l app.kubernetes.io/instance="$release" --timeout=5m
  "${kubectl_cmd[@]}" apply -f "$job_manifest"
  "${kubectl_cmd[@]}" -n "$namespace" wait --for=condition=complete \
    job/"$job_name" --timeout=60m
  "${kubectl_cmd[@]}" -n "$namespace" logs job/"$job_name" -c copy-config
  "${kubectl_cmd[@]}" -n "$namespace" logs job/"$job_name" -c copy-data
  protect_old_storage
}

protect_old_storage() {
  local claim pv
  for claim in adguard-home-config adguard-home-data; do
    pv="$("${kubectl_cmd[@]}" -n "$namespace" get pvc "$claim" -o jsonpath='{.spec.volumeName}')"
    [ -n "$pv" ] || { echo "Could not resolve PV for PVC $namespace/$claim" >&2; exit 1; }
    "${kubectl_cmd[@]}" -n "$namespace" patch pvc "$claim" --type=merge \
      -p '{"metadata":{"annotations":{"helm.sh/resource-policy":"keep"}}}'
    "${kubectl_cmd[@]}" patch pv "$pv" --type=merge \
      -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
  done
}

run_cutover() {
  require_confirmation "--phase cutover"
  if [ "$dry_run" -eq 1 ]; then
    "${helm_cmd[@]}" upgrade --install --dry-run=server --reuse-values \
      --namespace "$namespace" --version "$chart_version" "$release" "$chart_ref" \
      --set persistence.config.enabled=true \
      --set persistence.config.type=pvc \
      --set persistence.config.existingClaim=adguard-home-config-longhorn \
      --set persistence.data.enabled=true \
      --set persistence.data.type=pvc \
      --set persistence.data.existingClaim=adguard-home-data-longhorn
    return
  fi
  protect_old_storage
  "${helm_cmd[@]}" upgrade --install --reuse-values \
    --namespace "$namespace" --version "$chart_version" --wait --timeout 10m \
    "$release" "$chart_ref" \
    --set persistence.config.enabled=true \
    --set persistence.config.type=pvc \
    --set persistence.config.existingClaim=adguard-home-config-longhorn \
    --set persistence.config.mountPath=/opt/adguardhome/conf \
    --set persistence.data.enabled=true \
    --set persistence.data.type=pvc \
    --set persistence.data.existingClaim=adguard-home-data-longhorn \
    --set persistence.data.mountPath=/opt/adguardhome/work
  "${kubectl_cmd[@]}" -n "$namespace" rollout status deployment/"$deployment" --timeout=10m
  "${kubectl_cmd[@]}" -n "$namespace" get deploy "$deployment" \
    -o jsonpath='{.spec.template.spec.volumes[*].persistentVolumeClaim.claimName}{"\n"}'
}

if [ "$phase" = all ] || [ "$phase" = prepare ]; then run_prepare; fi
if [ "$phase" = all ] || [ "$phase" = copy ]; then run_copy; fi
if [ "$phase" = all ] || [ "$phase" = cutover ]; then run_cutover; fi

echo "AdGuard Home Longhorn migration phase '$phase' completed."
