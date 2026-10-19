#!/bin/bash

# Shared chart sources. OCI charts are listed individually because Helm does
# not index them through `helm repo add`.
truecharts_apps=(
  sonarr radarr bazarr jellyfin jellyseerr prowlarr plex homer flaresolverr scrutiny ddclient
  adguard-home jellystat duckdns filebot maintainerr plextraktsync proxmox-backup-server
  smokeping youtubedl-material cloudnative-pg prometheus-operator nginx-proxy-manager
  authelia pgadmin scrypted recyclarr readarr calibre bookstack audiobookshelf mailpile uptime-kuma ubooquity openbooks calibre-web
)

helm_chart_ref_for_app() {
  local app="$1"
  local truecharts_app
  local config_root
  local fleet_file
  local configured_ref

  config_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while IFS= read -r fleet_file; do
    configured_ref="$(awk -v app="$app" '
      /^name:[[:space:]]*/ { name=$2 }
      /^helm:[[:space:]]*$/ { in_helm=1; next }
      /^[^[:space:]#]/ { in_helm=0 }
      in_helm && /^[[:space:]]+chart:[[:space:]]*/ {
        chart=$2
        gsub(/[\042\047]/, "", chart)
      }
      END { if (name == app && chart ~ /^oci:\/\//) print chart }
    ' "$fleet_file")"
    if [ -n "$configured_ref" ]; then
      printf '%s\n' "$configured_ref"
      return 0
    fi
  done < <(find "$config_root/fleet" -type f -name fleet.yaml -print)

  for truecharts_app in "${truecharts_apps[@]}"; do
    if [ "$truecharts_app" = "$app" ]; then
      printf 'oci://oci.trueforge.org/truecharts/%s\n' "$app"
      return 0
    fi
  done
  return 1
}
