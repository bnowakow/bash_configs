#!/usr/bin/env bash

set -u
set -o pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
IMAGE_CHECKER="/home/sup/code/bash_configs/ovh/zabbix/is-docker-image-up-to-date.sh"
STARTUP_WAIT_SECONDS=${STARTUP_WAIT_SECONDS:-30}
LOG_FILE=${UPGRADE_DOCKER_IMAGES_LOG:-/tmp/upgrade-docker-images.log}

# Keep image checks here so adding the mysql/MariaDB deployment later only
# requires another entry.  The compose directory is also the working
# directory used for make upgrade and make codex-commit.
DEPLOYMENTS=(
  "n2nieruchomosci.pl|/home/sup/docker/n2nieruchomosci.pl|wordpress|wordpress"
  "bnowakowski.pl|/home/sup/docker/bnowakowski.pl|wordpress|wordpress"
  # "mysql|mysql|mariadb"
)

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  local message=$1
  printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$message" >>"$LOG_FILE"
}

: >"$LOG_FILE" || die "Could not write log file: $LOG_FILE"
log "starting script; log=$LOG_FILE"

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command is missing: $1"
}

show_message() {
  local title=$1 message=$2
  dialog --title "$title" --msgbox "$message" 15 90 </dev/tty >/dev/tty
}

confirm() {
  local title=$1 message=$2
  dialog --title "$title" --defaultno --yesno "$message" 18 90 </dev/tty >/dev/tty
}

latest_tag() {
  local image=$1 result newest checker_status response_file next_url page tag_count

  log "checking image=$image with checker=$IMAGE_CHECKER"
  result=$($IMAGE_CHECKER "$image" 2>>"$LOG_FILE") || {
    checker_status=$?
    log "checker failed image=$image status=$checker_status"
    return 1
  }
  log "checker output image=$image result=$(printf '%q' "$result")"
  if [[ "$result" != true ]]; then
    # The checker format is false,<old-running-images>,<newest-tag>.
    newest=$(printf '%s\n' "$result" | awk -F, '{ value=$NF; gsub(/[[:space:]]/, "", value); print value }')
    if [[ "$newest" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      printf '%s\n' "$newest"
      return 0
    fi
  fi

  # The checker returns only "true" when every matching container is current;
  # obtain the tag value from Docker Hub in that case.
  response_file=$(mktemp)
  next_url="https://registry.hub.docker.com/v2/repositories/library/${image}/tags?page_size=100"
  page=0
  : >"$response_file"
  while [[ -n "$next_url" ]]; do
    page=$((page + 1))
    if ! curl --fail --silent --show-error --location --max-time 30 "$next_url" \
        >"${response_file}.page" 2>>"$LOG_FILE"; then
      log "Docker Hub pagination stopped image=$image page=$page url=$next_url; using tags collected from $((page - 1)) pages"
      break
    fi
    tag_count=$(jq '.results | length' "${response_file}.page" 2>>"$LOG_FILE") || {
      log "invalid JSON from Docker Hub image=$image page=$page"
      rm -f "$response_file" "${response_file}.page"
      return 1
    }
    log "Docker Hub page image=$image page=$page tags=$tag_count"
    jq -r '.results[]?.name' "${response_file}.page" >>"$response_file"
    next_url=$(jq -r '.next // empty' "${response_file}.page")
  done
  newest=$(sed -nE 's/^([0-9]+\.[0-9]+\.[0-9]+)(-.+)?$/\1/p' "$response_file" |
    sort -V | tail -n 1)
  if [[ -z "$newest" ]]; then
    log "could not find a versioned WordPress tag across $page Docker Hub pages image=$image"
    rm -f "$response_file" "${response_file}.page"
    return 1
  fi
  log "selected newest base tag image=$image tag=$newest pages=$page"
  rm -f "$response_file" "${response_file}.page"
  [[ -n "$newest" ]] || return 1
  [[ "$newest" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  printf '%s\n' "$newest"
}

running_tag() {
  local container=$1 image_tag
  image_tag=$(docker inspect --format '{{.Config.Image}}' "$container" 2>/dev/null || true)
  [[ "$image_tag" == *:* ]] || return 1
  printf '%s\n' "${image_tag##*:}"
}

newer_tag() {
  printf '%s\n' "$@" | sort -V | tail -n 1
}

require_command docker
require_command curl
require_command make
require_command jq
require_command dialog
require_command git
if [[ ! -t 0 && ! -t 1 ]]; then
  die "This script must be run from an interactive terminal because it uses dialog."
fi
[[ -x "$IMAGE_CHECKER" ]] || die "Image checker is not executable: $IMAGE_CHECKER"

updates=()
for deployment in "${DEPLOYMENTS[@]}"; do
  IFS='|' read -r directory project_dir service image <<< "$deployment"
  compose_file="$project_dir/compose.yml"
  env_file="$project_dir/.env"
  [[ -f "$compose_file" && -f "$env_file" ]] || die "Missing compose or .env in $directory"

  current_tag=$(sed -n "s/^[[:space:]]*image:[[:space:]]*${image}:\([^[:space:]]*\).*/\1/p" "$compose_file" | head -n 1)
  [[ -n "$current_tag" ]] || die "Could not find ${image} image tag in $compose_file"
  domain=$(sed -n 's/^DOMAIN=//p' "$env_file" | head -n 1)
  [[ -n "$domain" ]] || die "DOMAIN is missing in $env_file"

  running_image_tag=$(running_tag "${domain}-${service}" || true)
  check_status=0
  newest_tag=$(latest_tag "$image") || check_status=$?
  if [[ $check_status -eq 2 ]]; then
    newest_tag=${running_image_tag:-$current_tag}
  elif [[ $check_status -ne 0 ]]; then
    log "fatal: could not determine newest tag image=$image; see $LOG_FILE"
    die "Could not determine the newest tag for $image (see $LOG_FILE)"
  fi

  desired_tag=$(newer_tag "$current_tag" "$newest_tag" "$running_image_tag")
  if [[ "$current_tag" != "$desired_tag" || ( -n "$running_image_tag" && "$running_image_tag" != "$current_tag" ) ]]; then
    updates+=("$directory|$project_dir|$compose_file|$service|$image|$current_tag|$desired_tag|$running_image_tag")
  fi
done

if ((${#updates[@]} == 0)); then
  show_message "Docker image updates" "All configured Docker images are up to date."
  exit 0
fi

summary=$'Available updates:\n\n'
for update in "${updates[@]}"; do
  IFS='|' read -r directory _ _ service image current_tag newest_tag running_image_tag <<< "$update"
  summary+="$directory ($service): compose $image:$current_tag"
  [[ -n "$running_image_tag" ]] && summary+="; running $image:$running_image_tag"
  summary+=" -> $image:$newest_tag"$'\n'
done
summary+=$'\nStart the upgrade now?'
confirm "Docker image updates" "$summary" || exit 0

completed_summary=$'Upgraded successfully:\n\n'
for update in "${updates[@]}"; do
  IFS='|' read -r directory project_dir compose_file service image old_tag new_tag running_image_tag <<< "$update"
  env_file="$project_dir/.env"
  domain=$(sed -n 's/^DOMAIN=//p' "$env_file" | head -n 1)
  [[ -n "$domain" ]] || die "DOMAIN is missing in $env_file"

  sed -i "s#^\([[:space:]]*image:[[:space:]]*${image}:\)[^[:space:]]*#\1${new_tag}#" "$compose_file"
  if ! make -C "$project_dir" upgrade; then
    show_message "Upgrade failed" "$directory: make upgrade failed. The compose file contains the new tag; inspect the deployment before retrying."
    exit 1
  fi

  sleep "$STARTUP_WAIT_SECONDS"
  if ! curl --fail --silent --show-error --location --max-time 30 "https://${domain}/" >/dev/null; then
    show_message "WordPress health check failed" "$directory did not respond successfully at https://${domain}/ after the upgrade. The old image was not deleted and no commit was made."
    exit 1
  fi

  if [[ "$old_tag" != "$new_tag" ]]; then
    old_image="${image}:${old_tag}"
    if docker ps --format '{{.Image}}' | grep -Fxq "$old_image"; then
      log "keeping old image still in use directory=$directory image=$old_image"
    else
      docker image rm "$old_image" || die "Could not delete unused old image $old_image"
    fi
  fi

  completed_summary+="$directory ($service): $image:$old_tag -> $image:$new_tag"$'\n'
done

if confirm "Commit Docker image updates" "$completed_summary\nCommit the compose file changes now?"; then
  for update in "${updates[@]}"; do
    IFS='|' read -r directory project_dir compose_file service image old_tag new_tag running_image_tag <<< "$update"
    git -C "$project_dir" add -- "$compose_file"
    make -C "$project_dir" codex-commit || die "codex-commit failed in $directory"
  done
else
  show_message "Docker image upgrade" "$completed_summary\nCompose changes were not committed."
  exit 0
fi

show_message "Docker image upgrade" "$completed_summary"
