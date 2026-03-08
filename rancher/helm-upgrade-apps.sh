#!/bin/bash

set -u

kubeconfig_path="/etc/rancher/k3s/k3s.yaml"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log_dir="$script_dir/logs"
timestamp="$(date +"%Y%m%d-%H%M%S")"
log_file="$log_dir/helm-upgrade-${timestamp}.log"
yes_mode=0
dry_run=0
exit_status=0
total_discovered_count=0
excluded_count=0
up_to_date_count=0
skipped_count=0
updated_count=0
dry_run_approved_count=0
failed_apps_count=0
failure_events_count=0
current_app=""
current_app_failed=0
use_color=1
blue=""
green=""
red=""
nc=""

# Keep excludes explicit and easy to maintain.
exclude_patterns=(
  '^cattle-'
  '^kube-system$'
  '^cert-manager$'
  '^cloudnative-pg$'
  '^longhorn-crd$'
  '^shinobi$'
  '^intel-device-plugins-operator$'
  '^node-feature-discovery$'
  '^meshcommander$'
  '^plex$'
)

is_up_to_date_helper="$script_dir/zabbix/is-helm-image-up-to-date.sh"
current_version_helper="$script_dir/zabbix/lib/helm-current-version-of-chart.sh"
chart_repo_helper="/etc/zabbix/zabbix_agent2.d/bash_configs/rancher/zabbix/lib/helm-chart-repo-dir-or-helm-repo.sh"
if [ ! -x "$chart_repo_helper" ]; then
  chart_repo_helper="$script_dir/zabbix/lib/helm-chart-repo-dir-or-helm-repo.sh"
fi

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--yes] [--dry-run] [--help]

Options:
  --yes       Auto-approve upgrades and continue prompts.
  --dry-run   Do not run helm upgrade; execute checks and prompts only.
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
    nc='\033[0m'
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

color_bash_rc() {
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
  else
    if [ "$use_color" -eq 1 ]; then
      printf '%b%s%b' "$red" "$label" "$nc"
    else
      printf '%s' "$label"
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

cleanup() {
  # Ensure cursor/screen is restored if dialog was used.
  if command -v dialog >/dev/null 2>&1; then
    dialog --clear >/dev/tty 2>/dev/null || true
  fi
}

show_log_window() {
  if [ "$yes_mode" -eq 1 ]; then
    return 0
  fi
  dialog \
    --clear \
    --title "Helm Upgrade Log" \
    --tailbox "$log_file" 20 120
}

show_summary_modal() {
  local summary
  summary="Discovered: $total_discovered_count
Excluded: $excluded_count
Up-to-date: $up_to_date_count
Skipped: $skipped_count
Updated: $updated_count"

  if [ "$dry_run" -eq 1 ]; then
    summary="${summary}
Dry-run approved (not executed): $dry_run_approved_count"
  fi

  summary="${summary}
Failed apps: $failed_apps_count
Failure events: $failure_events_count
Exit status: $exit_status
Log file: $log_file"

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
  local ingress_summary="$5"

  if [ "$yes_mode" -eq 1 ]; then
    log "AUTO: approving upgrade for $app"
    return 0
  fi

  dialog \
    --clear \
    --begin 0 0 \
    --title "Helm Upgrade Log" \
    --tailboxbg "$log_file" 18 120 \
    --and-widget \
    --begin 2 10 \
    --title "Upgrade $app?" \
    --defaultno \
    --yesno "App: $app\nNamespace: $namespace\nInstalled chart: ${local_version:-unknown}\nTarget chart: ${target_version:-unknown}\nHTTP checks:\n$ingress_summary\n\nProceed with upgrade?" 16 100
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
    --yesno "$message\n\nContinue with next app?" 14 100
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
  sudo /bin/helm ls --all-namespaces --kubeconfig "$kubeconfig_path" \
    | awk 'NR>1 {print $1}'
}

get_namespace_for_app() {
  local app="$1"
  sudo /bin/helm ls --all-namespaces --kubeconfig "$kubeconfig_path" \
    | awk -v app="$app" '$1==app {print $2; exit}'
}

get_local_chart_version() {
  local app="$1"
  sudo /bin/helm ls --all-namespaces --kubeconfig "$kubeconfig_path" \
    | awk -v app="$app" '$1==app {print $9; exit}'
}

get_ingress_hosts() {
  local namespace="$1"
  kubectl get ingress -n "$namespace" --kubeconfig "$kubeconfig_path" -o jsonpath='{range .items[*].spec.rules[*]}{.host}{"\n"}{end}' 2>/dev/null | awk 'NF' | sort -u
}

check_ingress_http_codes() {
  local app="$1"
  local namespace="$2"
  local phase="$3"

  ingress_summary="No ingress hosts found"

  local hosts
  hosts="$(get_ingress_hosts "$namespace")"

  if [ -z "$hosts" ]; then
    log "$app [$phase]: no ingress hosts found" "$(color_blue "$app") [$phase]: no ingress hosts found"
    return 0
  fi

  local fail=0
  local summary=""
  local host
  local http_code
  while IFS= read -r host; do
    [ -z "$host" ] && continue
    http_code="$(curl -L -s -o /dev/null -w "%{http_code}" "https://$host/")"
    summary="${summary}${host} -> ${http_code}\\n"
    log "$app [$phase]: ingress https://$host/ returned $http_code" "$(color_blue "$app") [$phase]: ingress https://$host/ returned $(color_http_code "$http_code")"
    if [ "$http_code" != "200" ]; then
      fail=1
    fi
  done <<EOF_HOSTS
$hosts
EOF_HOSTS

  ingress_summary="$(printf "%b" "$summary")"

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
  resources="$(kubectl get deployment,statefulset -n "$namespace" --kubeconfig "$kubeconfig_path" -o name 2>/dev/null || true)"

  if [ -z "$resources" ]; then
    log "$app [$phase]: no deployment/statefulset resources found" "$(color_blue "$app") [$phase]: no deployment/statefulset resources found"
    return 0
  fi

  local resource
  while IFS= read -r resource; do
    [ -z "$resource" ] && continue
    log "$app [$phase]: waiting for rollout status: $resource" "$(color_blue "$app") [$phase]: waiting for rollout status: $resource"
    if ! kubectl rollout status -n "$namespace" --kubeconfig "$kubeconfig_path" --timeout=300s "$resource" >>"$log_file" 2>&1; then
      log "$app [$phase]: rollout failed for $resource (rc=1)" "$(color_blue "$app") [$phase]: rollout failed for $resource (rc=$(color_bash_rc 1))"
      return 1
    fi
  done <<EOF_ROLLOUT
$resources
EOF_ROLLOUT

  log "$app [$phase]: rollout checks passed (rc=0)" "$(color_blue "$app") [$phase]: rollout checks passed (rc=$(color_bash_rc 0))"
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
    record_failure_and_maybe_abort "Precheck HTTP failed ($app)" "At least one ingress host for $app returned non-200."
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
    record_failure_and_maybe_abort "Postcheck HTTP failed ($app)" "At least one ingress host for $app returned non-200 after upgrade."
    return 1
  fi

  return 0
}

perform_upgrade() {
  local app="$1"
  local namespace="$2"
  local target_version="$3"
  local chart_ref="$4"

  if [ "$dry_run" -eq 1 ]; then
    log "$app: DRY RUN enabled, skipping helm upgrade" "$(color_blue "$app"): DRY RUN enabled, skipping helm upgrade"
    return 0
  fi

  if [ -z "$chart_ref" ]; then
    record_failure_and_maybe_abort "Missing chart reference ($app)" "Chart repo/ref helper returned empty value."
    return 1
  fi

  log "$app: running helm upgrade to version $target_version using chart $chart_ref" "$(color_blue "$app"): running helm upgrade to version $target_version using chart $chart_ref"
  if ! sudo helm upgrade \
    --kubeconfig "$kubeconfig_path" \
    --history-max=5 \
    --install=true \
    --namespace="$namespace" \
    --timeout=10m0s \
    --version="$target_version" \
    --wait=true \
    "$app" "$chart_ref" >>"$log_file" 2>&1; then
    record_failure_and_maybe_abort "Helm upgrade failed ($app)" "helm upgrade command failed (rc=1)."
    return 1
  fi

  log "$app: helm upgrade completed (rc=0)" "$(color_blue "$app"): helm upgrade completed (rc=$(color_bash_rc 0))"
  return 0
}

trap cleanup EXIT

mkdir -p "$log_dir"
: >"$log_file"

if ! require_cmd dialog || ! require_cmd helm || ! require_cmd kubectl || ! require_cmd curl || ! require_cmd sudo; then
  echo "Setup error: required dependency is missing." >&2
  exit 2
fi
if [ ! -x "$is_up_to_date_helper" ] || [ ! -x "$current_version_helper" ] || [ ! -x "$chart_repo_helper" ]; then
  echo "Setup error: one or more helper scripts are missing or not executable." >&2
  exit 2
fi

init_colors

log "Run started. log_file=$log_file yes_mode=$yes_mode dry_run=$dry_run"
log "Refreshing git and helm repos"
if ! sudo su zabbix -c "/home/sup/code/bash_configs/rancher/cron/git-pull.sh" >>"$log_file" 2>&1; then
  record_failure_and_maybe_abort "Git pull failed" "Unable to run rancher/cron/git-pull.sh as zabbix user."
else
  log "git pull refresh completed (rc=0)" "git pull refresh completed (rc=$(color_bash_rc 0))"
fi
if ! helm repo update >>"$log_file" 2>&1; then
  record_failure_and_maybe_abort "helm repo update failed" "Unable to refresh helm repos."
else
  log "helm repo update completed (rc=0)" "helm repo update completed (rc=$(color_bash_rc 0))"
fi

apps="$(list_candidate_apps)"
if [ -z "$apps" ]; then
  log "No helm apps discovered."
  show_log_window
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
  update_check_rc=$?
  helper_status="$(helper_status_label "$update_check_rc")"

  if [ "$update_check_rc" -eq 0 ] || [ "$update_check_rc" -eq 2 ]; then
    log "$app: no update needed (helper status: $helper_status, code: $update_check_rc)" "$(color_blue "$app"): no update needed (helper status: $(color_helper_status "$update_check_rc"), code: $(color_bash_rc "$update_check_rc"))"
    up_to_date_count=$((up_to_date_count + 1))
    current_app=""
    continue
  fi
  if [ "$update_check_rc" -ne 1 ]; then
    log "$app: unexpected helper status: $helper_status (code: $update_check_rc)" "$(color_blue "$app"): unexpected helper status: $(color_helper_status "$update_check_rc") (code: $(color_bash_rc "$update_check_rc"))"
    record_failure_and_maybe_abort "Update check failed ($app)" "is-helm-image-up-to-date.sh returned unexpected code $update_check_rc."
    current_app=""
    continue
  fi
  log "$app: update available (helper status: $helper_status)" "$(color_blue "$app"): update available (helper status: $(color_helper_status "$update_check_rc"))"

  namespace="$(get_namespace_for_app "$app")"
  if [ -z "$namespace" ]; then
    record_failure_and_maybe_abort "Namespace not found ($app)" "Unable to resolve namespace from helm ls output."
    current_app=""
    continue
  fi

  local_version="$(get_local_chart_version "$app")"
  target_version="$($current_version_helper "$app" --do-not-update-helm 2>>"$log_file")"
  chart_ref="$($chart_repo_helper "$app" 2>>"$log_file")"

  if [ -z "$target_version" ]; then
    record_failure_and_maybe_abort "Version lookup failed ($app)" "Current chart version helper returned empty version."
    current_app=""
    continue
  fi

  if ! run_prechecks "$app" "$namespace"; then
    current_app=""
    continue
  fi

  if show_app_modal "$app" "$namespace" "$local_version" "$target_version" "$ingress_summary"; then
    log "$app: upgrade approved" "$(color_blue "$app"): upgrade approved"
  else
    log "$app: upgrade skipped by user" "$(color_blue "$app"): upgrade skipped by user"
    skipped_count=$((skipped_count + 1))
    current_app=""
    continue
  fi

  if ! perform_upgrade "$app" "$namespace" "$target_version" "$chart_ref"; then
    current_app=""
    continue
  fi

  if [ "$dry_run" -eq 1 ]; then
    dry_run_approved_count=$((dry_run_approved_count + 1))
  else
    updated_count=$((updated_count + 1))
  fi

  run_postchecks "$app" "$namespace" || true
  log "$app: processing complete" "$(color_blue "$app"): processing complete"
  current_app=""
done

log "Run finished with exit status $exit_status"
show_summary_modal
show_log_window
exit "$exit_status"
