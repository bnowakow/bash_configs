#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubeconfig_path="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
phase="all"
yes_mode=0
dry_run=0

usage() {
  cat <<EOF
Usage: $0 <application> [--phase all|prepare|copy] [--yes] [--dry-run]

The application must be a subdirectory of:
  $script_dir

Phases:
  prepare   Apply the migration PVC manifest and wait for target PVCs to bind.
  copy      Stop the application, run the migration Job, and show its logs.
  all       Run prepare followed by copy (default).

--yes       Required for the copy phase because it stops the application.
--dry-run   Use server-side dry-run where supported; never stop the application.

After copy completes, apply that application's Helm values manually and scale
the application back up if the Helm upgrade does not do so automatically.
EOF
}

[ "$#" -ge 1 ] || { usage >&2; exit 2; }
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
  usage
  exit 0
fi
application="$1"
shift

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
  all|prepare|copy) ;;
  *) echo "Invalid phase: $phase" >&2; exit 2 ;;
esac

case "$application" in
  ''|.*|*/*|*[!a-zA-Z0-9._-]*)
    echo "Invalid application subdirectory: $application" >&2
    exit 2
    ;;
esac

app_dir="$script_dir/$application"
[ -d "$app_dir" ] || { echo "Migration directory not found: $app_dir" >&2; exit 1; }

if [ -f "$app_dir/pvc.yaml" ]; then
  pvc_manifest="$app_dir/pvc.yaml"
elif [ -f "$app_dir/${application}-migration-pvc.yaml" ]; then
  pvc_manifest="$app_dir/${application}-migration-pvc.yaml"
else
  echo "Could not find pvc.yaml or ${application}-migration-pvc.yaml in $app_dir" >&2
  exit 1
fi

if [ -f "$app_dir/copy-job.yaml" ]; then
  job_manifest="$app_dir/copy-job.yaml"
elif [ -f "$app_dir/${application}-migration-job.yaml" ]; then
  job_manifest="$app_dir/${application}-migration-job.yaml"
else
  echo "Could not find copy-job.yaml or ${application}-migration-job.yaml in $app_dir" >&2
  exit 1
fi

for command in kubectl; do
  command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 2; }
done

kubectl_cmd=(kubectl --kubeconfig "$kubeconfig_path")
namespace="apps-$application"
deployment="$application"
job_name="${application}-longhorn-migration"

require_confirmation() {
  if [ "$yes_mode" -ne 1 ]; then
    echo "The copy phase stops $namespace/$deployment. Re-run with --yes." >&2
    exit 2
  fi
}

run_prepare() {
  echo "Applying target PVCs for $application..."
  if [ "$dry_run" -eq 1 ]; then
    "${kubectl_cmd[@]}" apply --dry-run=server -f "$pvc_manifest"
    return
  fi
  "${kubectl_cmd[@]}" apply -f "$pvc_manifest"
  "${kubectl_cmd[@]}" wait --for=jsonpath='{.status.phase}'=Bound \
    -f "$pvc_manifest" --timeout=10m
}

run_copy() {
  require_confirmation

  if [ "$dry_run" -eq 1 ]; then
    "${kubectl_cmd[@]}" apply --dry-run=server -f "$job_manifest"
    return
  fi

  if "${kubectl_cmd[@]}" -n "$namespace" get job "$job_name" >/dev/null 2>&1; then
    echo "Job $namespace/$job_name already exists; inspect it before rerunning." >&2
    exit 1
  fi

  echo "Scaling $namespace/$deployment to zero..."
  "${kubectl_cmd[@]}" -n "$namespace" scale deployment "$deployment" --replicas=0
  "${kubectl_cmd[@]}" -n "$namespace" wait --for=delete \
    pod -l app.kubernetes.io/instance="$application" --timeout=5m

  echo "Applying migration Job..."
  "${kubectl_cmd[@]}" apply -f "$job_manifest"
  "${kubectl_cmd[@]}" -n "$namespace" wait --for=condition=complete \
    job/"$job_name" --timeout=60m
  "${kubectl_cmd[@]}" -n "$namespace" logs job/"$job_name"

  echo
  echo "Copy completed. Apply the Helm values for $application before restarting it."
}

if [ "$phase" = all ] || [ "$phase" = prepare ]; then
  run_prepare
fi
if [ "$phase" = all ] || [ "$phase" = copy ]; then
  run_copy
fi

echo "Migration phase '$phase' completed for $application."
