#!/bin/bash

set -u

kubeconfig_path="/etc/rancher/k3s/k3s.yaml"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash_configs_root="$(cd "$script_dir/.." && pwd)"
source "$script_dir/helm-repositories.sh"
log_dir="$script_dir/logs"
if [ ! -d "$log_dir" ] && ! mkdir -p "$log_dir" 2>/dev/null; then
  log_dir="${TMPDIR:-/tmp}/helm-upgrade-apps-logs"
  mkdir -p "$log_dir"
elif [ ! -w "$log_dir" ]; then
  log_dir="${TMPDIR:-/tmp}/helm-upgrade-apps-logs"
  mkdir -p "$log_dir"
fi
timestamp="$(date +"%Y%m%d-%H%M%S")"
log_file="$log_dir/helm-upgrade-${timestamp}.log"
yes_mode=0
dry_run=0
rollout_timeout="${ROLLOUT_TIMEOUT:-90s}"
exit_status=0
total_discovered_count=0
excluded_count=0
up_to_date_count=0
skipped_count=0
updated_count=0
staged_fleet_count=0
dry_run_approved_count=0
failed_apps_count=0
failure_events_count=0
version_check_error_apps=()
current_app=""
current_app_failed=0
insecure_hosts=""
check_summary_title=""
check_summary_body=""
check_summary_kind=""
use_color=1
dialog_colors_supported=0
dialog_success_color=2
dialog_success_attr="b"
blue=""
green=""
red=""
yellow=""
nc=""

# Keep excludes explicit and easy to maintain.
exclude_patterns=(
  '^cattle-'
  '^kube-system$'
  '^cert-manager$'
  '^cert-manager-resources$'
  '^cloudnative-pg$'
  '^longhorn-crd$'
  '^shinobi$'
  '^intel-device-plugins-operator$'
  '^node-feature-discovery$'
  '^meshcommander$'
  '^plex$'
  '^fleet$'
  '^fleet-agent-local$'
  '^fleet-crd$'
  '^rancher-turtles$'
  '^rancher-webhook$'
  '^system-upgrade-controller$'
  '^traefik$'
  '^traefik-config$'
  '^traefik-crd$'
  '^cleanuparr-localdomain-ingress$'
  '^profilarr-localdomain-ingress$'
)

is_up_to_date_helper="$script_dir/zabbix/is-helm-image-up-to-date.sh"
current_version_helper="$script_dir/zabbix/lib/helm-current-version-of-chart.sh"
chart_repo_helper="/etc/zabbix/zabbix_agent2.d/bash_configs/rancher/zabbix/lib/helm-chart-repo-dir-or-helm-repo.sh"
if [ ! -x "$chart_repo_helper" ]; then
  chart_repo_helper="$script_dir/zabbix/lib/helm-chart-repo-dir-or-helm-repo.sh"
fi

# Return the first exact chart match from Helm's configured repositories.
# `helm search repo` can return similarly named charts, so compare the chart
# name (the part after the final slash) rather than accepting the first row.
helm_exact_chart() {
  local app="$1"
  local configured_chart_ref

  configured_chart_ref="$(helm_chart_ref_for_app "$app" 2>/dev/null || true)"
  if [ -n "$configured_chart_ref" ]; then
    printf '%s\n' "$configured_chart_ref"
    return 0
  fi

  helm search repo "$app" --versions 2>/dev/null | awk -v app="$app" \
    'NR > 1 { name=$1; sub(/^.*\//, "", name); if (name == app) { print $1; exit } }'
}

chart_ref_for_app() {
  local app="$1"
  local chart_ref

  chart_ref="$(helm_exact_chart "$app")"
  if [ -n "$chart_ref" ]; then
    printf '%s\n' "$chart_ref"
    return 0
  fi

  # Some legacy/private charts are still only available in the local checkout.
  "$chart_repo_helper" "$app"
}

chart_version_for_app() {
  local app="$1"
  local chart_version
  local configured_chart_ref

  configured_chart_ref="$(helm_chart_ref_for_app "$app" 2>/dev/null || true)"
  if [ -n "$configured_chart_ref" ]; then
    helm show chart "$configured_chart_ref" 2>/dev/null | awk -F': *' '$1 == "version" { print $2; exit }'
    return 0
  fi

  chart_version="$(helm search repo "$app" --versions 2>/dev/null | awk -v app="$app" \
    'NR > 1 { name=$1; sub(/^.*\//, "", name); if (name == app) { print $2; exit } }')"
  if [ -n "$chart_version" ]; then
    printf '%s\n' "$chart_version"
    return 0
  fi

  # Fall back to the local chart only when Helm has no exact repository match.
  "$current_version_helper" "$app" --do-not-update-helm
}

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--yes] [--dry-run] [--rollout-timeout DURATION] [--help]

Options:
  --yes       Auto-approve upgrades and continue prompts.
  --dry-run   Do not apply Fleet changes; execute checks and prompts only.
  --rollout-timeout DURATION
              Timeout for each rollout status check (default: 90s).
  --help      Show this help message.

Exit codes:
  0 success/completed
  1 aborted by user or runtime failure
  2 dependency/setup error
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes)
      yes_mode=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --rollout-timeout)
      shift
      if [ "$#" -eq 0 ] || [ -z "$1" ]; then
        echo "Missing value for --rollout-timeout" >&2
        exit 2
      fi
      rollout_timeout="$1"
      shift
      ;;
    --rollout-timeout=*)
      rollout_timeout="${1#*=}"
      if [ -z "$rollout_timeout" ]; then
        echo "Missing value for --rollout-timeout" >&2
        exit 2
      fi
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

log() {
  local message="$1"
  local display_message="${2:-$1}"
  local ts
  ts="$(date +"%Y-%m-%d %H:%M:%S")"
  printf '[%s] %s\n' "$ts" "$message" >>"$log_file"
  printf '[%s] %b\n' "$ts" "$display_message"
}

init_colors() {
  if [ "${TERM:-}" = "dumb" ] || [ -n "${NO_COLOR:-}" ]; then
    use_color=0
  fi

  if [ "$use_color" -eq 1 ]; then
    blue='\033[1;94m'
    green='\033[0;32m'
    red='\033[0;31m'
    yellow='\033[0;33m'
    nc='\033[0m'
  fi
}

init_dialog_colors() {
  dialog_colors_supported=0
  if [ "$use_color" -eq 1 ] && command -v dialog >/dev/null 2>&1; then
    if dialog --help 2>&1 | grep -q -- '--colors'; then
      dialog_colors_supported=1
    fi
  fi
}

color_blue() {
  local text="$1"
  if [ "$use_color" -eq 1 ]; then
    printf '%b%s%b' "$blue" "$text" "$nc"
  else
    printf '%s' "$text"
  fi
}

color_http_code() {
  local code="$1"
  if [ "$code" = "200" ]; then
    if [ "$use_color" -eq 1 ]; then
      printf '%b%s%b' "$green" "$code" "$nc"
    else
      printf '%s' "$code"
    fi
  else
    if [ "$use_color" -eq 1 ]; then
      printf '%b%s%b' "$red" "$code" "$nc"
    else
      printf '%s' "$code"
    fi
  fi
}

dialog_color_app() {
  local text="$1"
  if [ "$use_color" -eq 1 ] && [ "$dialog_colors_supported" -eq 1 ]; then
    printf '\\Zb\\Z4%s\\Z0' "$text"
  else
    printf '%s' "$text"
  fi
}

dialog_color_http_code() {
  local code="$1"
  if [ "$code" = "200" ]; then
    if [ "$use_color" -eq 1 ] && [ "$dialog_colors_supported" -eq 1 ]; then
      local prefix="\\Z${dialog_success_attr}\\Z${dialog_success_color}"
      printf '%s%s\\Z0' "$prefix" "$code"
    else
      printf '%s' "$code"
    fi
  else
    if [ "$use_color" -eq 1 ] && [ "$dialog_colors_supported" -eq 1 ]; then
      printf '\\Z1%s\\Z0' "$code"
    else
      printf '%s' "$code"
    fi
  fi
}

color_bash_return_code() {
  local code="$1"
  if [ "$code" = "0" ]; then
    if [ "$use_color" -eq 1 ]; then
      printf '%b%s%b' "$green" "$code" "$nc"
    else
      printf '%s' "$code"
    fi
  else
    if [ "$use_color" -eq 1 ]; then
      printf '%b%s%b' "$red" "$code" "$nc"
    else
      printf '%s' "$code"
    fi
  fi
}

color_count() {
  local count="$1"
  local color="${2:-}"
  if [ "$use_color" -eq 1 ] && [ -n "$color" ]; then
    printf '%b%s%b' "$color" "$count" "$nc"
  else
    printf '%s' "$count"
  fi
}

color_zero_ok_count() {
  local count="$1"
  if [ "$count" -eq 0 ]; then
    color_count "$count" "$green"
  else
    color_count "$count" "$red"
  fi
}

helper_status_label() {
  local code="$1"
  case "$code" in
    0) printf 'up_to_date' ;;
    1) printf 'update_available' ;;
    2) printf 'local_newer_than_repo' ;;
    *) printf 'unknown' ;;
  esac
}

color_helper_status() {
  local code="$1"
  local label
  label="$(helper_status_label "$code")"
  if [ "$code" = "0" ]; then
    if [ "$use_color" -eq 1 ]; then
      printf '%b%s%b' "$green" "$label" "$nc"
    else
      printf '%s' "$label"
    fi
  elif [ "$code" = "1" ] || [ "$code" = "2" ]; then
    if [ "$use_color" -eq 1 ]; then
      printf '%b%s%b' "$yellow" "$label" "$nc"
    else
      printf '%s' "$label"
    fi
  else
    if [ "$use_color" -eq 1 ]; then
      printf '%b%s%b' "$red" "$label" "$nc"
    else
      printf '%s' "$label"
    fi
  fi
}

color_helper_code() {
  local code="$1"
  if [ "$code" = "0" ]; then
    if [ "$use_color" -eq 1 ]; then
      printf '%b%s%b' "$green" "$code" "$nc"
    else
      printf '%s' "$code"
    fi
  elif [ "$code" = "1" ] || [ "$code" = "2" ]; then
    if [ "$use_color" -eq 1 ]; then
      printf '%b%s%b' "$yellow" "$code" "$nc"
    else
      printf '%s' "$code"
    fi
  else
    if [ "$use_color" -eq 1 ]; then
      printf '%b%s%b' "$red" "$code" "$nc"
    else
      printf '%s' "$code"
    fi
  fi
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    return 1
  fi
  return 0
}

install_fleet_cli() {
  local download_file
  local fleet_url="https://github.com/rancher/fleet/releases/latest/download/fleet-linux-amd64"

  if ! command -v curl >/dev/null 2>&1; then
    echo "Cannot install Fleet CLI automatically because curl is missing." >&2
    return 1
  fi

  if [ "$yes_mode" -eq 1 ]; then
    log "AUTO: installing Fleet CLI from $fleet_url"
  elif ! command -v dialog >/dev/null 2>&1; then
    echo "Cannot ask whether to install Fleet CLI because dialog is missing." >&2
    return 1
  elif ! dialog \
    --clear \
    --title "Fleet CLI is missing" \
    --defaultno \
    --yesno "The Fleet CLI is required but is not installed.\n\nDownload and install it to /usr/local/bin/fleet now?" 12 80; then
    return 1
  fi

  download_file="$(mktemp "${TMPDIR:-/tmp}/fleet.XXXXXX")"
  log "Downloading Fleet CLI from $fleet_url"
  if ! curl -fL --retry 3 --connect-timeout 10 "$fleet_url" -o "$download_file" >>"$log_file" 2>&1; then
    rm -f "$download_file"
    echo "Fleet CLI download failed." >&2
    return 1
  fi
  chmod +x "$download_file"

  log "Installing Fleet CLI to /usr/local/bin/fleet"
  if ! sudo install -m 0755 "$download_file" /usr/local/bin/fleet >>"$log_file" 2>&1; then
    rm -f "$download_file"
    echo "Fleet CLI installation failed. You may need sudo access." >&2
    return 1
  fi
  rm -f "$download_file"

  if ! command -v fleet >/dev/null 2>&1; then
    echo "Fleet CLI installation completed, but fleet is still not in PATH." >&2
    return 1
  fi

  log "Fleet CLI installed: $(fleet --version 2>&1 | head -n 1)"
  return 0
}

fleet_file_for_app() {
  local app="$1"
  local fleet_file
  local fleet_name

  while IFS= read -r fleet_file; do
    fleet_name="$(awk -F': *' '$1 == "name" {print $2; exit}' "$fleet_file")"
    if [ "$fleet_name" = "$app" ]; then
      printf '%s\n' "$fleet_file"
      return 0
    fi
  done < <(find "$script_dir/fleet" -type f -name fleet.yaml -print)

  return 1
}

fleet_version_from_file() {
  local fleet_file="$1"
  awk -F': *' '$1 == "version" {print $2; exit}' "$fleet_file"
}

update_fleet_version() {
  local fleet_file="$1"
  local target_version="$2"
  local temporary_file

  temporary_file="$(mktemp "${TMPDIR:-/tmp}/fleet-version.XXXXXX")"
  if ! awk -v target_version="$target_version" '
    BEGIN { updated = 0 }
    !updated && $0 ~ /^[[:space:]]*version:[[:space:]]*/ {
      sub(/version:[[:space:]]*.*/, "version: " target_version)
      updated = 1
    }
    { print }
    END { if (!updated) exit 1 }
  ' "$fleet_file" >"$temporary_file"; then
    rm -f "$temporary_file"
    return 1
  fi

  mv "$temporary_file" "$fleet_file"
}

fleet_bundle_name_for_app() {
  local app="$1"
  local candidate="$app"
  local repo_name

  if ! kubectl get bundle -n fleet-local --kubeconfig "$kubeconfig_path" "$candidate" >/dev/null 2>&1; then
    return 1
  fi

  repo_name="$(kubectl get bundle -n fleet-local --kubeconfig "$kubeconfig_path" "$candidate" \
    -o jsonpath='{.metadata.labels.fleet\.cattle\.io/repo-name}' 2>/dev/null || true)"
  if [ "$repo_name" = "rancher-cluster" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  return 1
}

prepare_helm_upgrade_pvcs() {
  local app="$1"
  local namespace="$2"
  local target_version="$3"
  local fleet_file="$4"
  local chart_name
  local chart_label_name
  local release_name
  local target_chart_label
  local pvc_names
  local pvc_name
  local current_chart_label
  local storage_request
  local objectset_id

  chart_name="$(awk -F': *' '$1 == "  chart" {print $2; exit}' "$fleet_file")"
  release_name="$(awk -F': *' '$1 == "  releaseName" {print $2; exit}' "$fleet_file")"
  release_name="${release_name:-$app}"
  if [ -z "$chart_name" ]; then
    return 0
  fi

  # OCI chart refs include a URL prefix.  Helm's chart label uses only the
  # chart name, e.g. youtubedl-material-15.18.2, never oci-15.18.2.
  chart_label_name="${chart_name##*/}"
  target_chart_label="${chart_label_name}-${target_version}"
  objectset_id="default-${release_name}-cattle-fleet-local-system"
  pvc_names="$(kubectl get pvc --kubeconfig "$kubeconfig_path" --namespace "$namespace" \
    -l "app.kubernetes.io/instance=$release_name" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>>"$log_file" || true)"

  while IFS= read -r pvc_name; do
    [ -z "$pvc_name" ] && continue
    current_chart_label="$(kubectl get pvc "$pvc_name" \
      --kubeconfig "$kubeconfig_path" --namespace "$namespace" \
      -o jsonpath='{.metadata.labels.helm\.sh/chart}' 2>>"$log_file" || true)"
    if [ -n "$current_chart_label" ] && [ "$current_chart_label" != "$target_chart_label" ]; then
      log "$app: aligning PVC $pvc_name Helm chart label with target $target_chart_label" \
        "$(color_blue "$app"): aligning PVC metadata before Fleet upgrade"
      if ! printf 'apiVersion: v1\nkind: PersistentVolumeClaim\nmetadata:\n  name: %s\n  namespace: %s\n  labels:\n    helm.sh/chart: %s\n' \
        "$pvc_name" "$namespace" "$target_chart_label" | kubectl apply \
        --kubeconfig "$kubeconfig_path" \
        --server-side --force-conflicts --field-manager=helm \
        --filename - >>"$log_file" 2>&1; then
        record_failure_and_maybe_abort "Unable to prepare PVC ($app)" \
          "Could not transfer the Helm chart label on PVC $namespace/$pvc_name to Fleet's Helm manager. The PVC was not deleted."
        return 1
      fi
    fi

    # Fleet's Helm driver uses server-side apply.  A PVC created by an older
    # Helm release can still own the storage request field, which makes the
    # next Fleet reconciliation fail with a conflict such as:
    #   conflict with "helm" using v1: .spec.resources.requests.storage
    # Transfer only that mutable field to the same `helm` field manager.  Do
    # not apply the complete PVC object, since most PVC fields are immutable.
    storage_request="$(kubectl get pvc "$pvc_name" \
      --kubeconfig "$kubeconfig_path" --namespace "$namespace" \
      -o jsonpath='{.spec.resources.requests.storage}' 2>>"$log_file" || true)"
    if [ -n "$storage_request" ]; then
      log "$app: aligning PVC $pvc_name storage ownership for Fleet Helm" \
        "$(color_blue "$app"): aligning PVC storage ownership before Fleet upgrade"
      if ! printf 'apiVersion: v1\nkind: PersistentVolumeClaim\nmetadata:\n  name: %s\n  namespace: %s\nspec:\n  resources:\n    requests:\n      storage: %s\n' \
        "$pvc_name" "$namespace" "$storage_request" | kubectl apply \
        --kubeconfig "$kubeconfig_path" \
        --server-side --force-conflicts --field-manager=helm \
        --filename - >>"$log_file" 2>&1; then
        record_failure_and_maybe_abort "Unable to prepare PVC storage ownership ($app)" \
          "Could not transfer PVC $namespace/$pvc_name storage ownership to Fleet's Helm manager."
        return 1
      fi
    fi

    # Restored PVCs can retain Helm metadata while losing Fleet's objectset
    # ownership marker.  Fleet's Helm driver then refuses to manage the PVC
    # with "is not owned by us".  Restore only ownership metadata; never
    # delete or recreate the data-bearing PVC.
    log "$app: aligning PVC $pvc_name Fleet ownership metadata" \
      "$(color_blue "$app"): aligning PVC Fleet ownership metadata"
    if ! kubectl annotate pvc "$pvc_name" \
      --kubeconfig "$kubeconfig_path" --namespace "$namespace" \
      "objectset.rio.cattle.io/id=$objectset_id" \
      "meta.helm.sh/release-name=$release_name" \
      "meta.helm.sh/release-namespace=$namespace" \
      --overwrite >>"$log_file" 2>&1; then
      record_failure_and_maybe_abort "Unable to prepare PVC ownership ($app)" \
        "Could not restore Fleet ownership metadata on PVC $namespace/$pvc_name. The PVC was not deleted."
      return 1
    fi
    if ! kubectl label pvc "$pvc_name" \
      --kubeconfig "$kubeconfig_path" --namespace "$namespace" \
      app.kubernetes.io/managed-by=Helm --overwrite >>"$log_file" 2>&1; then
      record_failure_and_maybe_abort "Unable to prepare PVC labels ($app)" \
        "Could not restore Helm ownership labels on PVC $namespace/$pvc_name. The PVC was not deleted."
      return 1
    fi
  done <<< "$pvc_names"
}

fleet_bundledeployment_failure_message() {
  local bundledeployment_namespace="$1"
  local bundledeployment_name="$2"
  local message

  message="$(kubectl get bundledeployment "$bundledeployment_name" \
    --kubeconfig "$kubeconfig_path" --namespace "$bundledeployment_namespace" \
    -o jsonpath='{range .status.conditions[?(@.status=="False")]}{.type}: {.reason}: {.message}{"\n"}{end}{.status.display.message}' \
    2>>"$log_file" || true)"
  # Fleet reports a transient Ready error while a Deployment is replacing its
  # old pod, for example: "progressing ... minimum availability, Replicas:
  # 0/1".  That is not a failed Helm reconciliation; allow the readiness loop
  # to wait for the rollout.  Persistent conflicts and other actual errors are
  # still returned immediately.
  if printf '%s' "$message" | grep -Eiq 'failed|failure|error|conflict|unable|forbidden|invalid' && \
    ! printf '%s' "$message" | grep -Eiq 'progressing|does not have minimum availability|replicas:[[:space:]]*[0-9]+/[1-9]|job in progress|status:[[:space:]]*inprogress|post-upgrade hooks failed.*context deadline exceeded'; then
    printf '%s\n' "$message"
  fi
}

apply_fleet_bundle() {
  local app="$1"
  local fleet_dir="$2"
  local namespace="$3"
  local target_version="$4"
  local bundle_name
  local relative_fleet_dir
  local generated_bundle_file
  local bundle_generation
  local bundle_force_sync_generation
  local previous_applied_deployment_id
  local bundledeployment_namespace
  local bundledeployment_name
  local desired_deployment_id
  local current_desired_deployment_id
  local bundledeployment_lookup_attempts=0
  local bundledeployment_wait_attempts=0
  local applied_deployment_id
  local bundledeployment_ready
  local failure_message

  bundle_name="$(fleet_bundle_name_for_app "$app")" || {
    record_failure_and_maybe_abort "Fleet bundle not found ($app)" \
      "Expected GitRepo-managed bundle named $app in namespace fleet-local."
    return 1
  }

  relative_fleet_dir="${fleet_dir#"$bash_configs_root/"}"
  if [ "$relative_fleet_dir" = "$fleet_dir" ]; then
    record_failure_and_maybe_abort "Fleet path is outside repository ($app)" \
      "Fleet CLI requires a repository-relative path for $fleet_dir."
    return 1
  fi

  generated_bundle_file="$(mktemp "${TMPDIR:-/tmp}/fleet-bundle.XXXXXX.yaml")"
  log "$app: generating local Fleet Bundle from $relative_fleet_dir" \
    "$(color_blue "$app"): generating local Fleet Bundle"
  if ! (cd "$bash_configs_root" && fleet apply \
    --kubeconfig "$kubeconfig_path" \
    --namespace fleet-local \
    --output "$generated_bundle_file" \
    "$bundle_name" "$relative_fleet_dir") >>"$log_file" 2>&1; then
    rm -f "$generated_bundle_file"
    record_failure_and_maybe_abort "Fleet apply failed ($app)" \
      "fleet apply could not generate bundle $bundle_name. No cluster resources were changed."
    return 1
  fi

  if ! prepare_helm_upgrade_pvcs "$app" "$namespace" "$target_version" "$fleet_dir/fleet.yaml"; then
    rm -f "$generated_bundle_file"
    return 1
  fi

  previous_applied_deployment_id="$(kubectl get bundledeployment -A \
    --kubeconfig "$kubeconfig_path" \
    -l "fleet.cattle.io/bundle-name=$bundle_name" \
    -o jsonpath='{.items[0].status.appliedDeploymentID}' 2>>"$log_file" || true)"

  log "$app: applying generated Fleet Bundle $bundle_name" \
    "$(color_blue "$app"): applying generated Fleet Bundle $bundle_name"
  if ! bundle_generation="$(kubectl apply \
    --kubeconfig "$kubeconfig_path" \
    --namespace fleet-local \
    --server-side \
    --force-conflicts \
    --field-manager=codex-fleet-upgrade \
    --filename "$generated_bundle_file" \
    -o jsonpath='{.metadata.generation}' 2>>"$log_file")"; then
    rm -f "$generated_bundle_file"
    record_failure_and_maybe_abort "Fleet Bundle apply failed ($app)" \
      "kubectl could not apply the generated bundle $bundle_name."
    return 1
  fi

  # Applying the same chart version can leave the Bundle generation unchanged
  # (for example after a failed retry).  An annotation does not change
  # metadata.generation, so increment Fleet's forceSyncGeneration spec field
  # to request a real reconciliation and avoid reading stale status.
  bundle_force_sync_generation="$(kubectl get bundle "$bundle_name" \
    --kubeconfig "$kubeconfig_path" --namespace fleet-local \
    -o jsonpath='{.spec.forceSyncGeneration}' 2>>"$log_file" || true)"
  if ! [[ "$bundle_force_sync_generation" =~ ^[0-9]+$ ]]; then
    bundle_force_sync_generation=0
  fi
  bundle_force_sync_generation=$((bundle_force_sync_generation + 1))
  if ! bundle_generation="$(kubectl patch bundle "$bundle_name" \
    --kubeconfig "$kubeconfig_path" --namespace fleet-local \
    --type=merge \
    --patch "{\"spec\":{\"forceSyncGeneration\":$bundle_force_sync_generation}}" \
    -o jsonpath='{.metadata.generation}' 2>>"$log_file")"; then
    record_failure_and_maybe_abort "Fleet reconciliation request failed ($app)" \
      "Could not request a fresh reconciliation for bundle $bundle_name."
    return 1
  fi
  rm -f "$generated_bundle_file"

  log "$app: waiting for Fleet to observe bundle generation $bundle_generation" \
    "$(color_blue "$app"): waiting for Fleet to observe bundle generation $bundle_generation"
  if ! kubectl wait \
    --kubeconfig "$kubeconfig_path" \
    --namespace fleet-local \
    --timeout=10m \
    --for="jsonpath={.status.observedGeneration}=$bundle_generation" \
    "bundle/$bundle_name" >>"$log_file" 2>&1; then
    record_failure_and_maybe_abort "Fleet reconciliation did not start ($app)" \
      "Fleet did not observe generation $bundle_generation for bundle $bundle_name."
    return 1
  fi

  bundledeployment_namespace=""
  bundledeployment_name=""
  while { [ -z "$bundledeployment_namespace" ] || [ -z "$bundledeployment_name" ]; } && \
    [ "$bundledeployment_lookup_attempts" -lt 600 ]; do
    bundledeployment_namespace="$(kubectl get bundledeployment -A \
      --kubeconfig "$kubeconfig_path" \
      -l "fleet.cattle.io/bundle-name=$bundle_name" \
      -o jsonpath='{.items[0].metadata.namespace}' 2>>"$log_file" || true)"
    bundledeployment_name="$(kubectl get bundledeployment -A \
      --kubeconfig "$kubeconfig_path" \
      -l "fleet.cattle.io/bundle-name=$bundle_name" \
      -o jsonpath='{.items[0].metadata.name}' 2>>"$log_file" || true)"
    if [ -n "$bundledeployment_namespace" ] && [ -n "$bundledeployment_name" ]; then
      break
    fi
    bundledeployment_lookup_attempts=$((bundledeployment_lookup_attempts + 1))
    sleep 1
  done

  if [ -z "$bundledeployment_namespace" ] || [ -z "$bundledeployment_name" ]; then
    record_failure_and_maybe_abort "Fleet BundleDeployment not found ($app)" \
      "No BundleDeployment appeared for bundle $bundle_name within 10 minutes."
    return 1
  fi

  desired_deployment_id="$(kubectl -n "$bundledeployment_namespace" get bundledeployment "$bundledeployment_name" \
    --kubeconfig "$kubeconfig_path" -o jsonpath='{.spec.deploymentID}')"

  # Do not consume the previous deployment just because it is still exposed
  # while Fleet is processing the forced Bundle generation.  Wait until Fleet
  # publishes a different deployment ID before evaluating readiness/errors.
  if [ -n "$previous_applied_deployment_id" ]; then
    bundledeployment_wait_attempts=0
    while [ "$desired_deployment_id" = "$previous_applied_deployment_id" ] && \
      [ "$bundledeployment_wait_attempts" -lt 120 ]; do
      sleep 1
      current_desired_deployment_id="$(kubectl -n "$bundledeployment_namespace" get bundledeployment "$bundledeployment_name" \
        --kubeconfig "$kubeconfig_path" -o jsonpath='{.spec.deploymentID}' 2>>"$log_file" || true)"
      [ -n "$current_desired_deployment_id" ] && desired_deployment_id="$current_desired_deployment_id"
      bundledeployment_wait_attempts=$((bundledeployment_wait_attempts + 1))
    done
  fi

  if [ "$desired_deployment_id" = "$previous_applied_deployment_id" ]; then
    record_failure_and_maybe_abort "Fleet did not create a new deployment ($app)" \
      "Fleet kept the previous deployment ID after the reconciliation request."
    return 1
  fi

  log "$app: waiting for Fleet BundleDeployment $bundledeployment_name to apply deployment $desired_deployment_id" \
    "$(color_blue "$app"): waiting for Fleet BundleDeployment to apply the new deployment"

  # `kubectl wait` cannot express "wait for appliedDeploymentID unless the
  # BundleDeployment has already failed".  Poll both states so a failed Helm
  # revision is reported immediately instead of leaving the script frozen for
  # ten minutes.
  while [ "$bundledeployment_wait_attempts" -lt 600 ]; do
    applied_deployment_id="$(kubectl -n "$bundledeployment_namespace" get bundledeployment "$bundledeployment_name" \
      --kubeconfig "$kubeconfig_path" -o jsonpath='{.status.appliedDeploymentID}' 2>>"$log_file" || true)"
    bundledeployment_ready="$(kubectl -n "$bundledeployment_namespace" get bundledeployment "$bundledeployment_name" \
      --kubeconfig "$kubeconfig_path" -o jsonpath='{.status.ready}' 2>>"$log_file" || true)"
    failure_message="$(fleet_bundledeployment_failure_message "$bundledeployment_namespace" "$bundledeployment_name")"

    # Ignore a failure belonging to the deployment that existed before this
    # run.  Fleet may briefly expose that status while creating the new one.
    if [ -n "$failure_message" ] && \
      { [ -z "$previous_applied_deployment_id" ] || \
        [ "$desired_deployment_id" != "$previous_applied_deployment_id" ]; }; then
      log "$app: Fleet BundleDeployment reported failure: $failure_message" \
        "$(color_blue "$app"): Fleet Helm reconciliation failed"
      record_failure_and_maybe_abort "Fleet Helm reconciliation failed ($app)" \
        "BundleDeployment $bundledeployment_name reported:\n$failure_message"
      return 1
    fi

    if [ "$applied_deployment_id" = "$desired_deployment_id" ]; then
      break
    fi

    bundledeployment_wait_attempts=$((bundledeployment_wait_attempts + 1))
    sleep 1
  done

  if [ "$applied_deployment_id" != "$desired_deployment_id" ]; then
    record_failure_and_maybe_abort "Fleet BundleDeployment did not apply ($app)" \
      "Fleet did not apply deployment $desired_deployment_id for bundle $bundle_name."
    return 1
  fi

  log "$app: waiting for Fleet BundleDeployment $bundledeployment_name to become Ready" \
    "$(color_blue "$app"): waiting for Fleet BundleDeployment to become Ready"
  bundledeployment_wait_attempts=0
  while [ "$bundledeployment_wait_attempts" -lt 600 ]; do
    bundledeployment_ready="$(kubectl -n "$bundledeployment_namespace" get bundledeployment "$bundledeployment_name" \
      --kubeconfig "$kubeconfig_path" -o jsonpath='{.status.ready}' 2>>"$log_file" || true)"
    failure_message="$(fleet_bundledeployment_failure_message "$bundledeployment_namespace" "$bundledeployment_name")"
    if [ -n "$failure_message" ] && \
      { [ -z "$previous_applied_deployment_id" ] || \
        [ "$desired_deployment_id" != "$previous_applied_deployment_id" ]; }; then
      log "$app: Fleet BundleDeployment reported failure: $failure_message" \
        "$(color_blue "$app"): Fleet Helm reconciliation failed"
      record_failure_and_maybe_abort "Fleet Helm reconciliation failed ($app)" \
        "BundleDeployment $bundledeployment_name reported:\n$failure_message"
      return 1
    fi
    if [ "$bundledeployment_ready" = "true" ]; then
      break
    fi
    bundledeployment_wait_attempts=$((bundledeployment_wait_attempts + 1))
    sleep 1
  done

  if [ "$bundledeployment_ready" != "true" ]; then
    record_failure_and_maybe_abort "Fleet BundleDeployment failed ($app)" \
      "Fleet BundleDeployment $bundledeployment_name did not become Ready."
    return 1
  fi

  local fleet_resource_counts
  fleet_resource_counts="$(kubectl get bundledeployment -A \
    --kubeconfig "$kubeconfig_path" \
    -l "fleet.cattle.io/bundle-name=$bundle_name" \
    -o jsonpath='{range .items[*]}{.status.resourceCounts.desiredReady} {.status.resourceCounts.ready}{"\n"}{end}' \
    2>>"$log_file" | awk 'NF {print; exit}')"
  if [ -z "$fleet_resource_counts" ] || [ "$fleet_resource_counts" = "0 0" ] || \
    [ "${fleet_resource_counts%% *}" != "${fleet_resource_counts##* }" ]; then
    record_failure_and_maybe_abort "Fleet deployed no ready resources ($app)" \
      "Bundle $bundle_name reported resource counts: ${fleet_resource_counts:-unknown}."
    return 1
  fi

  log "$app: Fleet bundle $bundle_name is Ready" \
    "$(color_blue "$app"): Fleet bundle $bundle_name is Ready"
  return 0
}

stage_fleet_file() {
  local fleet_file="$1"
  local relative_file

  relative_file="${fleet_file#"$bash_configs_root/"}"
  if ! git -C "$bash_configs_root" add -- "$relative_file" >>"$log_file" 2>&1; then
    record_failure_and_maybe_abort "Unable to stage Fleet file" "git add failed for $relative_file."
    return 1
  fi
  log "Staged $relative_file after successful Fleet and ingress checks."
  return 0
}

cleanup() {
  # Ensure cursor/screen is restored if dialog was used.
  if command -v dialog >/dev/null 2>&1; then
    dialog --clear >/dev/null 2>&1 || true
  fi
}

print_colored_summary() {
  printf '%b\n' "$(color_blue "Run Summary")"
  printf 'Discovered: %b\n' "$(color_count "$total_discovered_count" "$blue")"
  printf 'Excluded: %b\n' "$(color_count "$excluded_count" "$yellow")"
  printf 'Up-to-date: %b\n' "$(color_count "$up_to_date_count" "$green")"
  printf 'Skipped: %b\n' "$(color_count "$skipped_count" "$yellow")"
  printf 'Updated: %b\n' "$(color_count "$updated_count" "$green")"
  printf 'Staged Fleet files: %b\n' "$(color_count "$staged_fleet_count" "$green")"

  if [ "$dry_run" -eq 1 ]; then
    printf 'Dry-run approved (not executed): %b\n' "$(color_count "$dry_run_approved_count" "$yellow")"
  fi

  printf 'Failed apps: %b\n' "$(color_zero_ok_count "$failed_apps_count")"
  printf 'Failure events: %b\n' "$(color_zero_ok_count "$failure_events_count")"
  if [ "${#version_check_error_apps[@]}" -gt 0 ]; then
    printf 'Helm version check errors: %s\n' "${version_check_error_apps[*]}"
  fi
  printf 'Exit status: %b\n' "$(color_bash_return_code "$exit_status")"
  printf 'Log file: %s\n' "$log_file"
}

show_summary_modal() {
  local summary
  summary="Discovered: $total_discovered_count
Excluded: $excluded_count
Up-to-date: $up_to_date_count
Skipped: $skipped_count
Updated: $updated_count
Staged Fleet files: $staged_fleet_count"

  if [ "$dry_run" -eq 1 ]; then
    summary="${summary}
Dry-run approved (not executed): $dry_run_approved_count"
  fi

  summary="${summary}
Failed apps: $failed_apps_count
Failure events: $failure_events_count"

  if [ "${#version_check_error_apps[@]}" -gt 0 ]; then
    summary="${summary}
Helm version check errors: ${version_check_error_apps[*]}"
  fi

  summary="${summary}
Exit status: $exit_status
Log file: $log_file"

  if [ "$updated_count" -eq 0 ]; then
    local ts
    ts="$(date +"%Y-%m-%d %H:%M:%S")"
    cleanup
    trap - EXIT
    print_colored_summary
    printf '[%s] Summary: discovered=%s excluded=%s up_to_date=%s skipped=%s updated=%s dry_run_approved=%s failed_apps=%s failure_events=%s exit_status=%s\n' "$ts" "$total_discovered_count" "$excluded_count" "$up_to_date_count" "$skipped_count" "$updated_count" "$dry_run_approved_count" "$failed_apps_count" "$failure_events_count" "$exit_status" >>"$log_file"
    return 0
  fi

  if [ "$yes_mode" -eq 1 ]; then
    log "Summary: discovered=$total_discovered_count excluded=$excluded_count up_to_date=$up_to_date_count skipped=$skipped_count updated=$updated_count dry_run_approved=$dry_run_approved_count failed_apps=$failed_apps_count failure_events=$failure_events_count exit_status=$exit_status"
    return 0
  fi

  dialog \
    --clear \
    --title "Run Summary" \
    --msgbox "$summary" 16 100
}

show_app_modal() {
  local app="$1"
  local namespace="$2"
  local local_version="$3"
  local target_version="$4"
  local summary_title="$5"
  local summary_body="$6"
  local dialog_color_flag=()
  local dialog_color_flag_yesno=()
  local app_display

  if [ "$yes_mode" -eq 1 ]; then
    log "AUTO: approving upgrade for $app"
    return 0
  fi

  if [ "$dialog_colors_supported" -eq 1 ]; then
    dialog_color_flag=(--colors)
    dialog_color_flag_yesno=(--colors)
  fi

  app_display="$(dialog_color_app "$app")"
  summary_body="${summary_body}\\Z0"

  dialog \
    "${dialog_color_flag[@]}" \
    --clear \
    --begin 0 0 \
    --title "Helm Upgrade Log" \
    --tailboxbg "$log_file" 18 120 \
    --and-widget \
    "${dialog_color_flag_yesno[@]}" \
    --begin 2 10 \
    --title "Upgrade $app?" \
    --defaultno \
    --yesno "App: $app_display\nNamespace: $namespace\nInstalled chart: ${local_version:-unknown}\nTarget chart: ${target_version:-unknown}\n${summary_title}:\n$summary_body\\Z0\n\nProceed with upgrade?" 24 120
}

show_postcheck_log_review_modal() {
  local app="$1"
  local namespace="$2"
  local summary_title="$3"
  local summary_body="$4"

  if [ "$yes_mode" -eq 1 ]; then
    log "AUTO: accepting postcheck pod log review for $app"
    return 0
  fi

  dialog \
    --clear \
    --begin 0 0 \
    --title "Helm Upgrade Log" \
    --tailboxbg "$log_file" 18 120 \
    --and-widget \
    --begin 2 10 \
    --title "Post-upgrade review for $app" \
    --yes-label "Looks good" \
    --no-label "Does not" \
    --defaultno \
    --yesno "Namespace: $namespace\n${summary_title}:\n$summary_body\n\nDo these logs look good after the upgrade?" 24 120
}

ask_on_failure() {
  local title="$1"
  local message="$2"

  if [ "$yes_mode" -eq 1 ]; then
    log "AUTO: failure encountered, continuing because --yes is set ($title)"
    return 0
  fi

  dialog \
    --clear \
    --begin 0 0 \
    --title "Helm Upgrade Log" \
    --tailboxbg "$log_file" 18 120 \
    --and-widget \
    --begin 2 10 \
    --title "$title" \
    --defaultno \
    --yesno "$message\n\nContinue with next app?" 20 120
}

last_deployed_revision() {
  local app="$1"
  local namespace="$2"

  helm history "$app" \
    --kubeconfig "$kubeconfig_path" \
    --max 20 \
    --namespace "$namespace" 2>>"$log_file" \
    | awk 'NR > 1 && $1 ~ /^[0-9]+$/ && $3 == "deployed" { revision = $1 } END { if (revision != "") print revision }'
}

ask_on_helm_upgrade_failure() {
  local app="$1"
  local namespace="$2"
  local revision="$3"
  local choice_file
  local choice

  if [ "$yes_mode" -eq 1 ] || [ -z "$revision" ]; then
    if [ -z "$revision" ]; then
      log "$app: no previously deployed Helm revision found; rollback is unavailable"
    fi
    ask_on_failure "Helm upgrade failed ($app)" "helm upgrade command failed (return_code=1)."
    return $?
  fi

  choice_file="$(mktemp "${TMPDIR:-/tmp}/helm-upgrade-failure-choice.XXXXXX")"
  if dialog \
    --clear \
    --begin 0 0 \
    --title "Helm Upgrade Log" \
    --tailboxbg "$log_file" 18 120 \
    --and-widget \
    --begin 2 10 \
    --title "Helm upgrade failed ($app)" \
    --default-item 1 \
    --menu "helm upgrade command failed (return_code=1).\n\nA previously deployed revision is available. What should happen next?" 16 110 3 \
    1 "Rollback to revision $revision" \
    2 "Continue with next app" \
    3 "Abort run" \
    2>"$choice_file"; then
    choice="$(<"$choice_file")"
  else
    choice=3
  fi
  rm -f "$choice_file"

  case "$choice" in
    1)
      log "$app: rolling back to previously deployed Helm revision $revision" "$(color_blue "$app"): rolling back to previously deployed Helm revision $revision"
      if helm rollback \
        --kubeconfig "$kubeconfig_path" \
        --namespace "$namespace" \
        --timeout=10m0s \
        --wait=true \
        "$app" "$revision" >>"$log_file" 2>&1; then
        log "$app: rollback to Helm revision $revision completed (return_code=0)" "$(color_blue "$app"): rollback to Helm revision $revision completed (return_code=$(color_bash_return_code 0))"
        return 0
      fi
      log "$app: rollback to Helm revision $revision failed (return_code=1)" "$(color_blue "$app"): rollback to Helm revision $revision failed (return_code=$(color_bash_return_code 1))"
      if ask_on_failure "Helm rollback failed ($app)" "helm rollback to revision $revision failed (return_code=1)."; then
        log "User chose to continue after rollback failure."
        return 0
      fi
      log "User aborted run after rollback failure."
      cleanup
      exit 1
      ;;
    2)
      log "User chose to continue after Helm upgrade failure."
      return 0
      ;;
    *)
      log "User aborted run after Helm upgrade failure."
      cleanup
      exit 1
      ;;
  esac
}

host_uses_insecure() {
  local host="$1"
  printf '%s\n' "$insecure_hosts" | grep -F -x -q "$host"
}

add_insecure_host() {
  local host="$1"
  if ! host_uses_insecure "$host"; then
    if [ -n "$insecure_hosts" ]; then
      insecure_hosts="${insecure_hosts}
$host"
    else
      insecure_hosts="$host"
    fi
  fi
}

curl_error_looks_like_certificate_validity_issue() {
  local curl_return_code="$1"
  local curl_error_output="$2"
  if printf '%s' "$curl_error_output" | grep -E -i -q 'certificate has expired|certificate.*not yet valid|SSL certificate problem|peer certificate|certificate verify failed|x509:|tlsv1|ssl routines|ssl.*certificate|tls.*certificate'; then
    return 0
  fi

  case "$curl_return_code" in
    35|51|58|59|60|77|83|90)
      return 0
      ;;
  esac

  if [ "$curl_return_code" = "60" ]; then
    return 0
  fi

  return 1
}

ask_retry_curl_with_insecure() {
  local host="$1"
  local curl_error_output="$2"

  if [ "$yes_mode" -eq 1 ]; then
    log "AUTO: not retrying curl with --insecure for $host because --yes is set"
    return 1
  fi

  dialog \
    --clear \
    --begin 0 0 \
    --title "Helm Upgrade Log" \
    --tailboxbg "$log_file" 18 120 \
    --and-widget \
    --begin 2 10 \
    --title "Certificate Validity Issue" \
    --defaultno \
    --yesno "curl failed for https://$host/ and it looks like the certificate may be out of date.\n\nError:\n$curl_error_output\n\nRetry this host with --insecure to skip certificate validity checks?" 18 100
}

run_curl_http_check() {
  local host="$1"
  local curl_error_file
  local curl_args=(-L -sS -o /dev/null -w "%{http_code}")

  curl_http_code="000"
  curl_return_code=1
  curl_used_insecure=0
  curl_error_output=""

  if host_uses_insecure "$host"; then
    curl_args+=(--insecure)
    curl_used_insecure=1
  fi

  curl_error_file="$(mktemp)"
  if curl_http_code="$(curl "${curl_args[@]}" "https://$host/" 2>"$curl_error_file")"; then
    curl_return_code=0
    curl_error_output=""
    rm -f "$curl_error_file"
    return 0
  fi

  curl_return_code=$?
  curl_error_output="$(cat "$curl_error_file")"
  rm -f "$curl_error_file"

  if [ "$curl_used_insecure" -eq 0 ] && curl_error_looks_like_certificate_validity_issue "$curl_return_code" "$curl_error_output"; then
    log "curl for https://$host/ failed due to certificate validity issue (return_code=$curl_return_code)"
    if ask_retry_curl_with_insecure "$host" "$curl_error_output"; then
      add_insecure_host "$host"
      curl_used_insecure=1
      curl_error_file="$(mktemp)"
      if curl_http_code="$(curl -L -sS --insecure -o /dev/null -w "%{http_code}" "https://$host/" 2>"$curl_error_file")"; then
        curl_return_code=0
        curl_error_output=""
        rm -f "$curl_error_file"
        log "curl for https://$host/ succeeded after retry with --insecure"
        return 0
      fi
      curl_return_code=$?
      curl_error_output="$(cat "$curl_error_file")"
      rm -f "$curl_error_file"
    fi
  fi

  return 1
}

record_failure_and_maybe_abort() {
  local title="$1"
  local message="$2"
  exit_status=1
  failure_events_count=$((failure_events_count + 1))
  if [ -n "$current_app" ] && [ "$current_app_failed" -eq 0 ]; then
    current_app_failed=1
    failed_apps_count=$((failed_apps_count + 1))
  fi
  log "FAILURE: $title - $message"
  if ask_on_failure "$title" "$message"; then
    log "User chose to continue after failure."
    return 0
  fi
  log "User aborted run after failure."
  cleanup
  exit 1
}

should_exclude_app() {
  local app="$1"
  local pattern
  for pattern in "${exclude_patterns[@]}"; do
    if [[ "$app" =~ $pattern ]]; then
      return 0
    fi
  done
  return 1
}

list_candidate_apps() {
  helm ls --all-namespaces --kubeconfig "$kubeconfig_path" \
    | awk 'NR>1 {print $1}'
}

get_namespace_for_app() {
  local app="$1"
  helm ls --all-namespaces --kubeconfig "$kubeconfig_path" \
    | awk -v app="$app" '$1==app {print $2; exit}'
}

get_local_chart_version() {
  local app="$1"
  helm ls --all-namespaces --kubeconfig "$kubeconfig_path" \
    | awk -v app="$app" '$1==app {print $9; exit}'
}

get_ingress_hosts() {
  local namespace="$1"
  kubectl get ingress -n "$namespace" --kubeconfig "$kubeconfig_path" -o jsonpath='{range .items[*].spec.rules[*]}{.host}{"\n"}{end}' 2>/dev/null | awk 'NF' | sort -u
}

get_release_pods() {
  local app="$1"
  local namespace="$2"
  kubectl get pods -n "$namespace" --kubeconfig "$kubeconfig_path" -l "app.kubernetes.io/instance=$app" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | awk 'NF' | sort -u
}

collect_no_ingress_pod_log_summary() {
  local app="$1"
  local namespace="$2"
  local phase="$3"
  local pods
  local summary=""
  local pod
  local pod_logs
  local line

  check_summary_title="Pod logs (last 10 lines per pod)"
  check_summary_kind="pod-logs"

  pods="$(get_release_pods "$app" "$namespace")"
  if [ -z "$pods" ]; then
    check_summary_body="No release-labeled pods found for app.kubernetes.io/instance=$app"
    log "$app [$phase]: no ingress hosts found and no release-labeled pods were found for pod log review" "$(color_blue "$app") [$phase]: no ingress hosts found and no release-labeled pods were found for pod log review"
    return 0
  fi

  while IFS= read -r pod; do
    [ -z "$pod" ] && continue
    log "$app [$phase]: collecting last 10 log lines for pod $pod" "$(color_blue "$app") [$phase]: collecting last 10 log lines for pod $pod"
    pod_logs="$(kubectl logs -n "$namespace" --kubeconfig "$kubeconfig_path" --all-containers=true --tail=10 "$pod" 2>&1 || true)"
    summary="${summary}Pod: $pod"$'\n'
    if [ -n "$pod_logs" ]; then
      while IFS= read -r line; do
        summary="${summary}  $line"$'\n'
      done <<<"$pod_logs"
    else
      summary="${summary}  <no log output>"$'\n'
    fi
    summary="${summary}"$'\n'
  done <<EOF_PODS
$pods
EOF_PODS

  check_summary_body="${summary%$'\n'}"
  log "$app [$phase]: no ingress hosts found, using pod log review instead" "$(color_blue "$app") [$phase]: no ingress hosts found, using pod log review instead"
  return 0
}

check_ingress_http_codes() {
  local app="$1"
  local namespace="$2"
  local phase="$3"

  check_summary_title="HTTP checks"
  check_summary_body="No ingress hosts found"
  check_summary_kind="http"
  check_failed_ingress_summary=""

  local hosts
  hosts="$(get_ingress_hosts "$namespace")"

  if [ -z "$hosts" ]; then
    collect_no_ingress_pod_log_summary "$app" "$namespace" "$phase"
    return 0
  fi

  local fail=0
  local summary=""
  local host
  local http_code
  local dialog_code
  local insecure_suffix
  local failed_summary=""
  while IFS= read -r host; do
    [ -z "$host" ] && continue
    run_curl_http_check "$host"
    http_code="$curl_http_code"
    dialog_code="$(dialog_color_http_code "$http_code")"
    insecure_suffix=""
    if [ "$curl_used_insecure" -eq 1 ]; then
      insecure_suffix=" (with --insecure)"
    fi
    summary="${summary}\\Z0${host} -> ${dialog_code}${insecure_suffix}\\Z0"$'\n'
    log "$app [$phase]: ingress https://$host/ returned $http_code${insecure_suffix}" "$(color_blue "$app") [$phase]: ingress https://$host/ returned $(color_http_code "$http_code")${insecure_suffix}"
    if [ "$curl_return_code" != "0" ]; then
      log "$app [$phase]: curl failed for https://$host/ (return_code=$curl_return_code) error=$curl_error_output" "$(color_blue "$app") [$phase]: curl failed for https://$host/ (return_code=$(color_bash_return_code "$curl_return_code"))"
      failed_summary="${failed_summary}${host} -> ${http_code} (curl failed, return code ${curl_return_code})"$'\n'
      fail=1
    elif [ "$http_code" != "200" ]; then
      failed_summary="${failed_summary}${host} -> ${http_code}"$'\n'
      fail=1
    fi
  done <<EOF_HOSTS
$hosts
EOF_HOSTS

  check_summary_body="${summary%$'\n'}"
  check_failed_ingress_summary="${failed_summary%$'\n'}"

  if [ "$fail" -eq 1 ]; then
    return 1
  fi
  return 0
}

check_rollout_ready() {
  local app="$1"
  local namespace="$2"
  local phase="$3"

  local resources
  resources="$(kubectl get deployment,statefulset -n "$namespace" --kubeconfig "$kubeconfig_path" -l "app.kubernetes.io/instance=$app" -o name 2>/dev/null || true)"

  if [ -z "$resources" ]; then
    log "$app [$phase]: no release-labeled deployment/statefulset resources found for app.kubernetes.io/instance=$app" "$(color_blue "$app") [$phase]: no release-labeled deployment/statefulset resources found for app.kubernetes.io/instance=$app"
    return 0
  fi

  local resource
  while IFS= read -r resource; do
    [ -z "$resource" ] && continue
    log "$app [$phase]: waiting for rollout status: $resource (timeout=$rollout_timeout)" "$(color_blue "$app") [$phase]: waiting for rollout status: $resource (timeout=$rollout_timeout)"
    if ! kubectl rollout status -n "$namespace" --kubeconfig "$kubeconfig_path" --timeout="$rollout_timeout" "$resource" >>"$log_file" 2>&1; then
      log "$app [$phase]: rollout failed for $resource (return_code=1)" "$(color_blue "$app") [$phase]: rollout failed for $resource (return_code=$(color_bash_return_code 1))"
      return 1
    fi
  done <<EOF_ROLLOUT
$resources
EOF_ROLLOUT

  log "$app [$phase]: rollout checks passed (return_code=0)" "$(color_blue "$app") [$phase]: rollout checks passed (return_code=$(color_bash_return_code 0))"
  return 0
}

run_prechecks() {
  local app="$1"
  local namespace="$2"

  if ! check_rollout_ready "$app" "$namespace" "precheck"; then
    record_failure_and_maybe_abort "Precheck rollout failed ($app)" "Workload rollout status failed in namespace $namespace."
    return 1
  fi

  if ! check_ingress_http_codes "$app" "$namespace" "precheck"; then
    record_failure_and_maybe_abort "Precheck HTTP failed ($app)" "Failed ingress hosts for $app:\n$check_failed_ingress_summary"
    return 1
  fi

  return 0
}

run_postchecks() {
  local app="$1"
  local namespace="$2"

  if ! check_rollout_ready "$app" "$namespace" "postcheck"; then
    record_failure_and_maybe_abort "Postcheck rollout failed ($app)" "Workload rollout status failed in namespace $namespace."
    return 1
  fi

  if ! check_ingress_http_codes "$app" "$namespace" "postcheck"; then
    record_failure_and_maybe_abort "Postcheck HTTP failed ($app)" "Failed ingress hosts for $app after upgrade:\n$check_failed_ingress_summary"
    return 1
  fi

  if [ "$check_summary_kind" = "pod-logs" ]; then
    if ! show_postcheck_log_review_modal "$app" "$namespace" "$check_summary_title" "$check_summary_body"; then
      record_failure_and_maybe_abort "Postcheck pod log review failed ($app)" "Pod logs did not look good after upgrade in namespace $namespace."
      return 1
    fi
    log "$app [postcheck]: pod log review accepted" "$(color_blue "$app") [postcheck]: pod log review accepted"
  fi

  return 0
}

perform_upgrade() {
  local app="$1"
  local namespace="$2"
  local target_version="$3"
  local fleet_file="$4"

  if [ "$dry_run" -eq 1 ]; then
    log "$app: DRY RUN enabled, skipping Fleet apply" "$(color_blue "$app"): DRY RUN enabled, skipping Fleet apply"
    return 0
  fi

  if [ -z "$fleet_file" ]; then
    record_failure_and_maybe_abort "Fleet file not found ($app)" "No matching fleet.yaml was found under $script_dir/fleet."
    return 1
  fi

  log "$app: updating Fleet version to $target_version in $fleet_file" \
    "$(color_blue "$app"): updating Fleet version to $target_version"
  if ! update_fleet_version "$fleet_file" "$target_version"; then
    record_failure_and_maybe_abort "Unable to update Fleet file ($app)" \
      "Could not replace the version field in $fleet_file."
    return 1
  fi

  apply_fleet_bundle "$app" "$(dirname "$fleet_file")" "$namespace" "$target_version"
}

ask_run_codex_commit() {
  if [ "$staged_fleet_count" -eq 0 ]; then
    return 0
  fi

  if [ "$yes_mode" -eq 1 ]; then
    log "AUTO: running make codex-commit because --yes is set"
  elif ! dialog \
    --clear \
    --title "Commit Fleet upgrades" \
    --defaultno \
    --yesno "Fleet upgrades passed their rollout and ingress checks and were staged.\n\nRun:\nmake -C $bash_configs_root codex-commit\n\nRun it now?" 14 90; then
    log "User chose not to run make codex-commit; staged Fleet files were left in place."
    return 0
  fi

  log "Running make -C $bash_configs_root codex-commit"
  if ! make -C "$bash_configs_root" codex-commit >>"$log_file" 2>&1; then
    record_failure_and_maybe_abort "codex-commit failed" "make codex-commit returned a failure."
    return 1
  fi
  log "make codex-commit completed successfully."
  return 0
}

trap cleanup EXIT

mkdir -p "$log_dir"
: >"$log_file"

if ! command -v fleet >/dev/null 2>&1; then
  if ! install_fleet_cli; then
    cat >&2 <<'FLEET_MISSING'
Missing required command: fleet

Install the Fleet CLI on Debian with:
  curl -L -o /tmp/fleet https://github.com/rancher/fleet/releases/latest/download/fleet-linux-amd64
  chmod +x /tmp/fleet
  sudo install -m 0755 /tmp/fleet /usr/local/bin/fleet
  fleet --version

The Fleet CLI is separate from the Fleet controllers already running in Rancher.
FLEET_MISSING
    exit 2
  fi
fi

if ! require_cmd dialog || ! require_cmd helm || ! require_cmd kubectl || ! require_cmd curl || ! require_cmd git || ! require_cmd make; then
  echo "Setup error: required dependency is missing." >&2
  exit 2
fi
if [ ! -x "$is_up_to_date_helper" ] || [ ! -x "$current_version_helper" ] || [ ! -x "$chart_repo_helper" ]; then
  echo "Setup error: one or more helper scripts are missing or not executable." >&2
  exit 2
fi

init_colors
init_dialog_colors

log "Run started. log_file=$log_file yes_mode=$yes_mode dry_run=$dry_run rollout_timeout=$rollout_timeout"
log "Refreshing helm repos"
if ! helm repo update >>"$log_file" 2>&1; then
  record_failure_and_maybe_abort "helm repo update failed" "Unable to refresh helm repos."
else
  log "helm repo update completed (return_code=0)" "helm repo update completed (return_code=$(color_bash_return_code 0))"
fi

apps="$(list_candidate_apps)"
if [ -z "$apps" ]; then
  log "No helm apps discovered."
  exit "$exit_status"
fi

for app in $apps; do
  total_discovered_count=$((total_discovered_count + 1))
  current_app="$app"
  current_app_failed=0

  if should_exclude_app "$app"; then
  log "$app: excluded by pattern" "$(color_blue "$app"): excluded by pattern"
    excluded_count=$((excluded_count + 1))
    current_app=""
    continue
  fi

  log "$app: checking if update is available" "$(color_blue "$app"): checking if update is available"
  "$is_up_to_date_helper" "$app" --do-not-update-helm >>"$log_file" 2>&1
  update_check_return_code=$?
  helper_status="$(helper_status_label "$update_check_return_code")"

  if [ "$update_check_return_code" -eq 0 ] || [ "$update_check_return_code" -eq 2 ]; then
    log "$app: no update needed (helper status: $helper_status, return_code: $update_check_return_code)" "$(color_blue "$app"): no update needed (helper status: $(color_helper_status "$update_check_return_code"), return_code: $(color_helper_code "$update_check_return_code"))"
    up_to_date_count=$((up_to_date_count + 1))
    current_app=""
    continue
  fi
  if [ "$update_check_return_code" -ne 1 ]; then
    if [ "$update_check_return_code" -eq 3 ]; then
      version_check_error_apps+=("$app")
    fi
    log "$app: unexpected helper status: $helper_status (return_code: $update_check_return_code)" "$(color_blue "$app"): unexpected helper status: $(color_helper_status "$update_check_return_code") (return_code: $(color_helper_code "$update_check_return_code"))"
    record_failure_and_maybe_abort "Update check failed ($app)" "is-helm-image-up-to-date.sh returned unexpected return_code $update_check_return_code."
    current_app=""
    continue
  fi
  log "$app: update available (helper status: $helper_status)" "$(color_blue "$app"): update available (helper status: $(color_helper_status "$update_check_return_code"))"

  namespace="$(get_namespace_for_app "$app")"
  if [ -z "$namespace" ]; then
    record_failure_and_maybe_abort "Namespace not found ($app)" "Unable to resolve namespace from helm ls output."
    current_app=""
    continue
  fi

  local_version="$(get_local_chart_version "$app")"
  target_version="$(chart_version_for_app "$app" 2>>"$log_file")"
  fleet_file="$(fleet_file_for_app "$app" 2>/dev/null || true)"

  if [ -z "$target_version" ]; then
    record_failure_and_maybe_abort "Version lookup failed ($app)" "Current chart version helper returned empty version."
    current_app=""
    continue
  fi

  # The image checker can report an application-image update even when the
  # configured Helm chart repository has no newer chart.  Never reconcile a
  # no-op chart version through Fleet; it can create a new Helm revision and
  # unnecessarily reprocess PVCs and other resources.
  installed_chart_version="${local_version#"$app-"}"
  if [ -n "$installed_chart_version" ] && [ "$installed_chart_version" = "$target_version" ]; then
    log "$app: no chart update needed (installed=$installed_chart_version target=$target_version)" \
      "$(color_blue "$app"): no chart update needed (installed=$installed_chart_version target=$target_version)"
    up_to_date_count=$((up_to_date_count + 1))
    current_app=""
    continue
  fi

  if ! run_prechecks "$app" "$namespace"; then
    current_app=""
    continue
  fi

  if show_app_modal "$app" "$namespace" "$local_version" "$target_version" "$check_summary_title" "$check_summary_body"; then
    log "$app: upgrade approved" "$(color_blue "$app"): upgrade approved"
  else
    log "$app: upgrade skipped by user" "$(color_blue "$app"): upgrade skipped by user"
    skipped_count=$((skipped_count + 1))
    current_app=""
    continue
  fi

  if ! perform_upgrade "$app" "$namespace" "$target_version" "$fleet_file"; then
    current_app=""
    continue
  fi

  if [ "$dry_run" -eq 1 ]; then
    dry_run_approved_count=$((dry_run_approved_count + 1))
  else
    updated_count=$((updated_count + 1))
  fi

  if run_postchecks "$app" "$namespace"; then
    if [ "$dry_run" -eq 0 ]; then
      if stage_fleet_file "$fleet_file"; then
        staged_fleet_count=$((staged_fleet_count + 1))
      fi
    fi
  else
    log "$app: postchecks did not pass; Fleet file was not staged" \
      "$(color_blue "$app"): postchecks did not pass; Fleet file was not staged"
  fi
  log "$app: processing complete" "$(color_blue "$app"): processing complete"
  current_app=""
done

log "Run finished with exit status $exit_status"
show_summary_modal
if [ "$exit_status" -eq 0 ]; then
  ask_run_codex_commit || true
fi
exit "$exit_status"
