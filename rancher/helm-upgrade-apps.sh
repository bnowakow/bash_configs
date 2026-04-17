#!/bin/bash

set -u

kubeconfig_path="/etc/rancher/k3s/k3s.yaml"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log_dir="$script_dir/logs"
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
dry_run_approved_count=0
failed_apps_count=0
failure_events_count=0
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
Usage: $(basename "$0") [--yes] [--dry-run] [--rollout-timeout DURATION] [--help]

Options:
  --yes       Auto-approve upgrades and continue prompts.
  --dry-run   Do not run helm upgrade; execute checks and prompts only.
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

cleanup() {
  # Ensure cursor/screen is restored if dialog was used.
  if command -v dialog >/dev/null 2>&1; then
    dialog --clear >/dev/tty 2>/dev/null || true
  fi
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
    --yesno "$message\n\nContinue with next app?" 14 100
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
      fail=1
    elif [ "$http_code" != "200" ]; then
      fail=1
    fi
  done <<EOF_HOSTS
$hosts
EOF_HOSTS

  check_summary_body="${summary%$'\n'}"

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
    record_failure_and_maybe_abort "Helm upgrade failed ($app)" "helm upgrade command failed (return_code=1)."
    return 1
  fi

  log "$app: helm upgrade completed (return_code=0)" "$(color_blue "$app"): helm upgrade completed (return_code=$(color_bash_return_code 0))"
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
init_dialog_colors

log "Run started. log_file=$log_file yes_mode=$yes_mode dry_run=$dry_run rollout_timeout=$rollout_timeout"
log "Refreshing git and helm repos"
if ! sudo su zabbix -c "/home/sup/code/bash_configs/rancher/cron/git-pull.sh" >>"$log_file" 2>&1; then
  record_failure_and_maybe_abort "Git pull failed" "Unable to run rancher/cron/git-pull.sh as zabbix user."
else
  log "git pull refresh completed (return_code=0)" "git pull refresh completed (return_code=$(color_bash_return_code 0))"
fi
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

  if show_app_modal "$app" "$namespace" "$local_version" "$target_version" "$check_summary_title" "$check_summary_body"; then
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
exit "$exit_status"
