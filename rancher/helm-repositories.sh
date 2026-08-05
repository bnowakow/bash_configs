#!/bin/bash

# Shared chart sources. OCI charts are listed individually because Helm does
# not index them through `helm repo add`.
truecharts_apps=(
  sonarr radarr bazarr jellyfin jellyseerr prowlarr plex homer flaresolverr scrutiny
  adguard-home jellystat duckdns filebot maintainerr plextraktsync proxmox-backup-server
  smokeping youtubedl-material cloudnative-pg prometheus-operator nginx-proxy-manager
  authelia pgadmin scrypted recyclarr readarr calibre bookstack
)

helm_chart_ref_for_app() {
  local app="$1"
  local truecharts_app
  for truecharts_app in "${truecharts_apps[@]}"; do
    if [ "$truecharts_app" = "$app" ]; then
      printf 'oci://oci.trueforge.org/truecharts/%s\n' "$app"
      return 0
    fi
  done
  return 1
}
