#!/bin/bash

add_rancher_repo() {
repo_name=$1
repo_url=$2
cat <<EOF | kubectl apply -f -
apiVersion: catalog.cattle.io/v1
kind: ClusterRepo
metadata:
  name: $repo_name
spec:
  url: $repo_url
EOF
}

add_rancher_repo_git() {
repo_name=$1
repo_url=$2
repo_branch=$3
cat <<EOF | kubectl apply -f -
apiVersion: catalog.cattle.io/v1
kind: ClusterRepo
metadata:
  name: $repo_name
spec:
  gitRepo: $repo_url
  gitBranch: $repo_branch
EOF
}

# trucharts
# https://truecharts.org/charts/description-list/
for true_chart_repo_name in sonarr radarr bazarr jellyfin jellyseerr prowlarr plex homer bazarr flaresolverr scrutiny \
    adguard-home jellystat duckdns filebot maintainerr plextraktsync proxmox-backup-server scrutiny smokeping \
    youtubedl-material cloudnative-pg prometheus-operator nginx-proxy-manager authelia pgadmin scrypted recyclarr readarr \
    calibre; do
    add_rancher_repo "truecharts-$true_chart_repo_name" "oci://tccr.io/truecharts/$true_chart_repo_name"
done

add_rancher_repo "zabbix-community" "https://zabbix-community.github.io/helm-zabbix"
add_rancher_repo "docker-mailserver" "https://docker-mailserver.github.io/docker-mailserver-helm/"
add_rancher_repo "elastic" "https://helm.elastic.co"
add_rancher_repo "bitnamicharts-postgresql" "oci://registry-1.docker.io/bitnamicharts/postgresql"
add_rancher_repo "mlohr-roundcube" "https://helm-charts.mlohr.com/"
add_rancher_repo "cloudnative-pg" "https://cloudnative-pg.github.io/charts"
add_rancher_repo "cloudcasa-vendor" "https://catalogicsoftware.github.io/cloudcasa-helmchart"

# TODO meshcommander
# TODO shinobi
# TODO youtubedl-material
# TODO node-feature-discovery 	intel-device-plugins-operator 	intel-device-plugins-gpu 


