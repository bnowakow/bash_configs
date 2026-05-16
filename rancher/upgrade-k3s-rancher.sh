#!/bin/bash

set -Eeuo pipefail

kubeconfig_path="/etc/rancher/k3s/k3s.yaml"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log_dir="$script_dir/logs"
timestamp="$(date +"%Y%m%d-%H%M%S")"
log_file="$log_dir/upgrade-k3s-rancher-${timestamp}.log"
rancher_matrix_index_url="https://www.suse.com/suse-rancher/support-matrix/all-supported-versions/"
rancher_matrix_current_url="https://www.suse.com/suse-rancher/support-matrix"
k3s_releases_api_url="https://api.github.com/repos/k3s-io/k3s/releases?per_page=100"
cert_manager_releases_api_url="https://api.github.com/repos/cert-manager/cert-manager/releases?per_page=100"
rollout_timeout="${ROLLOUT_TIMEOUT:-10m}"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--help]

Upgrades the current k3s server node, cert-manager, and Rancher.

The script discovers current compatible versions from SUSE/GitHub, prints the
selected versions and source URLs, attempts a pre-upgrade k3s snapshot, and then
waits for confirmation before making upgrade changes.

Environment:
  ROLLOUT_TIMEOUT   kubectl rollout timeout for Rancher deployment (default: 10m)
USAGE
}

log() {
  local message="$1"
  local ts
  ts="$(date +"%Y-%m-%d %H:%M:%S")"
  printf '[%s] %s\n' "$ts" "$message" | tee -a "$log_file"
}

run_cmd() {
  log "+ $*"
  "$@" 2>&1 | tee -a "$log_file"
}

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "This script must be run as root." >&2
    exit 2
  fi
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    return 1
  fi
}

require_dependencies() {
  local missing=0
  local cmd
  for cmd in awk base64 chmod cp curl grep helm hostname kubectl mkdir sed sleep sort systemctl tail tee tr; do
    if ! require_cmd "$cmd"; then
      missing=1
    fi
  done

  if [ "$missing" -ne 0 ]; then
    exit 2
  fi
}

confirm() {
  local prompt="$1"
  local answer
  printf '%s [y/N] ' "$prompt"
  read -r answer
  case "$answer" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

fetch_url() {
  local url="$1"
  curl -fsSL "$url"
}

fetch_effective_url() {
  local url="$1"
  curl -fsSL -o /dev/null -w '%{url_effective}' "$url"
}

strip_html_tags() {
  sed -E 's/<[^>]*>/ /g; s/&nbsp;/ /g; s/&#160;/ /g; s/&amp;/\&/g'
}

highest_semver_tag() {
  sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -n 1
}

parse_latest_rancher_url() {
  local effective_url="$1"
  local index_html="$2"
  local candidate

  if printf '%s\n' "$effective_url" | grep -Eq '/rancher-v[0-9]+-[0-9]+-[0-9]+/?$'; then
    printf '%s\n' "$effective_url"
    return 0
  fi

  candidate="$(
    printf '%s\n' "$index_html" |
      grep -Eo 'https://www\.suse\.com/suse-rancher/support-matrix/all-supported-versions/rancher-v[0-9]+-[0-9]+-[0-9]+/?|/suse-rancher/support-matrix/all-supported-versions/rancher-v[0-9]+-[0-9]+-[0-9]+/?' |
      sed -E 's#^/suse-rancher#https://www.suse.com/suse-rancher#; s#/$##' |
      sed -E 's#.*rancher-v([0-9]+)-([0-9]+)-([0-9]+).*#\1.\2.\3 &#' |
      sort -t. -k1,1n -k2,2n -k3,3n |
      tail -n 1 |
      awk '{print $2}'
  )"

  if [ -z "$candidate" ]; then
    return 1
  fi

  printf '%s/\n' "$candidate"
}

parse_rancher_version_from_url() {
  local url="$1"
  printf '%s\n' "$url" | sed -E 's#.*rancher-v([0-9]+)-([0-9]+)-([0-9]+)/?.*#v\1.\2.\3#'
}

parse_supported_k3s_minor() {
  local matrix_html="$1"
  local text
  text="$(printf '%s\n' "$matrix_html" | tr '\n' ' ' | strip_html_tags | tr -s ' ')"

  printf '%s\n' "$text" |
    grep -Eoi 'k3s[[:space:]]+v[0-9]+\.[0-9]+[[:space:]]+v[0-9]+\.[0-9]+' |
    head -n 1 |
    awk '{print $3}'
}

json_release_tags() {
  grep -Eo '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' |
    sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'
}

select_k3s_release() {
  local releases_json="$1"
  local supported_minor="$2"
  local minor_without_v="${supported_minor#v}"
  local selected

  selected="$(
    printf '%s\n' "$releases_json" |
      json_release_tags |
      grep -E "^v${minor_without_v//./\\.}\\.[0-9]+\\+k3s[0-9]+$" |
      sed -E 's#^v([0-9]+\.[0-9]+\.[0-9]+)\+k3s([0-9]+)$#\1.\2 v\1+k3s\2#' |
      highest_semver_tag |
      awk '{print $2}'
  )"

  if [ -z "$selected" ]; then
    return 1
  fi

  printf '%s\n' "$selected"
}

select_cert_manager_release() {
  local releases_json="$1"
  local selected

  selected="$(
    printf '%s\n' "$releases_json" |
      json_release_tags |
      grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' |
      sed -E 's#^v([0-9]+\.[0-9]+\.[0-9]+)$#\1 v\1#' |
      highest_semver_tag |
      awk '{print $2}'
  )"

  if [ -z "$selected" ]; then
    return 1
  fi

  printf '%s\n' "$selected"
}

url_encode_k3s_version() {
  local version="$1"
  printf '%s\n' "${version/+/%2B}"
}

show_current_status() {
  log "Current status before upgrade:"

  if command -v k3s >/dev/null 2>&1; then
    run_cmd k3s --version || true
  else
    log "k3s command not found; this may be a fresh install or PATH issue."
  fi

  if [ -f "$kubeconfig_path" ]; then
    run_cmd kubectl --kubeconfig "$kubeconfig_path" get nodes || true
    run_cmd kubectl --kubeconfig "$kubeconfig_path" get pods --namespace cert-manager || true
    run_cmd kubectl --kubeconfig "$kubeconfig_path" get pods --namespace cattle-system || true
    run_cmd helm --kubeconfig "$kubeconfig_path" list --namespace cert-manager || true
    run_cmd helm --kubeconfig "$kubeconfig_path" list --namespace cattle-system || true
  else
    log "Kubeconfig does not exist yet: $kubeconfig_path"
  fi
}

save_snapshot_or_confirm() {
  if ! command -v k3s >/dev/null 2>&1; then
    log "Skipping k3s snapshot because k3s command is not available."
    confirm "Continue without a pre-upgrade k3s snapshot?" || exit 1
    return 0
  fi

  if run_cmd k3s etcd-snapshot save --name "pre-rancher-upgrade-${timestamp}"; then
    log "Pre-upgrade k3s snapshot completed."
    return 0
  fi

  log "Pre-upgrade k3s snapshot failed or is unavailable for this datastore."
  confirm "Continue without a successful pre-upgrade k3s snapshot?" || exit 1
}

wait_for_kubectl() {
  local attempt
  for attempt in $(seq 1 60); do
    if kubectl --kubeconfig "$kubeconfig_path" get nodes >/dev/null 2>&1; then
      run_cmd kubectl --kubeconfig "$kubeconfig_path" get nodes
      return 0
    fi
    log "Waiting for Kubernetes API to become reachable ($attempt/60)..."
    sleep 5
  done

  log "Kubernetes API did not become reachable in time."
  return 1
}

normalize_leading_v() {
  local version="$1"
  printf 'v%s\n' "${version#v}"
}

require_equal_version() {
  local component="$1"
  local expected="$2"
  local actual="$3"

  if [ "$(normalize_leading_v "$actual")" != "$(normalize_leading_v "$expected")" ]; then
    log "$component version check failed: expected $expected, got ${actual:-unknown}."
    return 1
  fi

  log "$component version check passed: $actual"
}

versions_match() {
  local actual="$1"
  local expected="$2"

  [ -n "$actual" ] && [ "$(normalize_leading_v "$actual")" = "$(normalize_leading_v "$expected")" ]
}

helm_release_field() {
  local release="$1"
  local namespace="$2"
  local field="$3"

  helm --kubeconfig "$kubeconfig_path" list \
    --namespace "$namespace" \
    --filter "^${release}$" \
    --output json |
    sed -nE "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\1/p" |
    head -n 1
}

installed_k3s_version() {
  if ! command -v k3s >/dev/null 2>&1; then
    return 1
  fi

  k3s --version | awk 'NR == 1 {print $3}'
}

skip_if_already_current() {
  local expected_k3s_version="$1"
  local expected_cert_manager_version="$2"
  local expected_rancher_version="$3"
  local actual_k3s_version
  local actual_cert_manager_version
  local actual_rancher_version

  log "Checking whether installed versions already match selected upgrade targets."

  actual_k3s_version="$(installed_k3s_version || true)"
  actual_cert_manager_version="$(helm_release_field cert-manager cert-manager app_version || true)"
  actual_rancher_version="$(helm_release_field rancher cattle-system app_version || true)"

  log "Installed k3s version: ${actual_k3s_version:-not detected}; target: $expected_k3s_version"
  log "Installed cert-manager app_version: ${actual_cert_manager_version:-not detected}; target: $expected_cert_manager_version"
  log "Installed Rancher app_version: ${actual_rancher_version:-not detected}; target: $expected_rancher_version"

  if versions_match "$actual_k3s_version" "$expected_k3s_version" &&
     versions_match "$actual_cert_manager_version" "$expected_cert_manager_version" &&
     versions_match "$actual_rancher_version" "$expected_rancher_version"; then
    log "All selected upgrade targets are already installed. No upgrade needed."
    exit 0
  fi
}

verify_final_versions() {
  local expected_k3s_version="$1"
  local expected_cert_manager_version="$2"
  local expected_rancher_version="$3"
  local actual_k3s_version
  local actual_cert_manager_version
  local actual_rancher_version
  local cert_manager_chart
  local rancher_chart

  log "Verifying installed versions against selected upgrade targets."

  actual_k3s_version="$(installed_k3s_version)"
  run_cmd k3s --version
  require_equal_version "k3s" "$expected_k3s_version" "$actual_k3s_version"

  actual_cert_manager_version="$(helm_release_field cert-manager cert-manager app_version)"
  cert_manager_chart="$(helm_release_field cert-manager cert-manager chart)"
  run_cmd helm --kubeconfig "$kubeconfig_path" list --namespace cert-manager --filter '^cert-manager$'
  require_equal_version "cert-manager app_version" "$expected_cert_manager_version" "$actual_cert_manager_version"
  log "cert-manager chart version reported by Helm: ${cert_manager_chart:-unknown}"

  actual_rancher_version="$(helm_release_field rancher cattle-system app_version)"
  rancher_chart="$(helm_release_field rancher cattle-system chart)"
  run_cmd helm --kubeconfig "$kubeconfig_path" list --namespace cattle-system --filter '^rancher$'
  require_equal_version "Rancher app_version" "$expected_rancher_version" "$actual_rancher_version"
  log "Rancher chart version reported by Helm: ${rancher_chart:-unknown}"

  log "All final version checks passed."
}

ensure_helm_repo() {
  local name="$1"
  local url="$2"

  if helm repo list 2>/dev/null | awk '{print $1}' | grep -Fxq "$name"; then
    log "Helm repo already exists: $name"
    return 0
  fi

  run_cmd helm repo add "$name" "$url"
}

main() {
  if [ "${1:-}" = "--help" ]; then
    usage
    exit 0
  fi

  if [ "$#" -gt 0 ]; then
    echo "Unknown argument: $1" >&2
    usage >&2
    exit 2
  fi

  require_root
  mkdir -p "$log_dir"
  require_dependencies
  export KUBECONFIG="$kubeconfig_path"

  log "Run started. log_file=$log_file"
  log "Discovering latest Rancher, k3s, and cert-manager versions."

  local rancher_effective_url
  local rancher_index_html
  local rancher_matrix_url
  local rancher_matrix_html
  local rancher_version
  local supported_k3s_minor
  local k3s_releases_json
  local k3s_version
  local k3s_install_version
  local cert_manager_releases_json
  local cert_manager_version
  local hostname_fqdn
  local setup_password

  rancher_effective_url="$(fetch_effective_url "$rancher_matrix_current_url")"
  rancher_index_html="$(fetch_url "$rancher_matrix_index_url" || true)"
  rancher_matrix_url="$(parse_latest_rancher_url "$rancher_effective_url" "$rancher_index_html")"
  rancher_matrix_html="$(fetch_url "$rancher_matrix_url")"
  rancher_version="$(parse_rancher_version_from_url "$rancher_matrix_url")"
  supported_k3s_minor="$(parse_supported_k3s_minor "$rancher_matrix_html")"

  if [ -z "$rancher_version" ] || [ -z "$supported_k3s_minor" ]; then
    log "Unable to discover Rancher version or supported k3s minor from SUSE support matrix."
    exit 1
  fi

  k3s_releases_json="$(fetch_url "$k3s_releases_api_url")"
  k3s_version="$(select_k3s_release "$k3s_releases_json" "$supported_k3s_minor")"
  cert_manager_releases_json="$(fetch_url "$cert_manager_releases_api_url")"
  cert_manager_version="$(select_cert_manager_release "$cert_manager_releases_json")"

  if [ -z "$k3s_version" ] || [ -z "$cert_manager_version" ]; then
    log "Unable to select k3s or cert-manager release from GitHub."
    exit 1
  fi

  k3s_install_version="$(url_encode_k3s_version "$k3s_version")"
  hostname_fqdn="$(hostname).tailscale.bnowakowski.pl"

  log "Selected Rancher version: $rancher_version"
  log "Rancher support matrix URL: $rancher_matrix_url"
  log "Supported k3s Kubernetes minor: $supported_k3s_minor"
  log "Selected k3s release: $k3s_version"
  log "k3s releases URL: https://github.com/k3s-io/k3s/releases"
  log "Selected cert-manager release: $cert_manager_version"
  log "cert-manager releases URL: https://github.com/cert-manager/cert-manager/releases"
  log "Rancher hostname: $hostname_fqdn"

  skip_if_already_current "$k3s_version" "$cert_manager_version" "$rancher_version"
  show_current_status
  save_snapshot_or_confirm

  cat <<SUMMARY

About to run the upgrade with:
  Rancher:       $rancher_version
  Rancher URL:   $rancher_matrix_url
  k3s minor:     $supported_k3s_minor
  k3s release:   $k3s_version
  cert-manager:  $cert_manager_version
  hostname:      $hostname_fqdn
  log file:      $log_file

SUMMARY

  confirm "Do these versions and settings look good?" || exit 1

  log "Upgrading k3s to $k3s_version."
  log "+ curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=\"$k3s_install_version\" sh -s - server"
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$k3s_install_version" sh -s - server 2>&1 | tee -a "$log_file"

  run_cmd cp "$script_dir/config.yaml" /etc/rancher/k3s/config.yaml
  run_cmd chmod 644 /etc/rancher/k3s/config.yaml
  run_cmd systemctl stop k3s
  run_cmd systemctl start k3s
  wait_for_kubectl

  ensure_helm_repo "rancher-stable" "https://releases.rancher.com/server-charts/stable"
  ensure_helm_repo "jetstack" "https://charts.jetstack.io"
  run_cmd helm repo update

  run_cmd helm --kubeconfig "$kubeconfig_path" upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --version "$cert_manager_version" \
    --set startupapicheck.timeout=5m \
    --set crds.enabled=true

  run_cmd kubectl --kubeconfig "$kubeconfig_path" apply --validate=false -f "https://github.com/jetstack/cert-manager/releases/download/$cert_manager_version/cert-manager.crds.yaml"
  run_cmd kubectl --kubeconfig "$kubeconfig_path" apply --validate=false -f "https://github.com/jetstack/cert-manager/releases/download/$cert_manager_version/cert-manager.crds.yaml"
  run_cmd kubectl --kubeconfig "$kubeconfig_path" get pods --namespace cert-manager

  run_cmd helm --kubeconfig "$kubeconfig_path" upgrade --install rancher rancher-stable/rancher \
    --namespace cattle-system \
    --create-namespace \
    --version "${rancher_version#v}" \
    --set "hostname=$hostname_fqdn" \
    --set bootstrapPassword=admin \
    --set ingress.tls.source=letsEncrypt \
    --set letsEncrypt.email=dobrowolski.nowakowski@gmail.com

  run_cmd kubectl --kubeconfig "$kubeconfig_path" -n cattle-system rollout status deploy/rancher --timeout="$rollout_timeout"
  run_cmd kubectl --kubeconfig "$kubeconfig_path" -n cattle-system get deploy rancher

  setup_password="$(kubectl --kubeconfig "$kubeconfig_path" get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}')"
  log "Rancher setup URL: https://$hostname_fqdn/dashboard/?setup=$setup_password"

  run_cmd "$script_dir/rancher_add_cluster_repos.sh"
  verify_final_versions "$k3s_version" "$cert_manager_version" "$rancher_version"

  log "Upgrade completed."
}

main "$@"
