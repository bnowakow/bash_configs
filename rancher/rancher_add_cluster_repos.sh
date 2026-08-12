#!/bin/bash

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml;

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/helm-repositories.sh"

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

# Keep the same repositories available to the local Helm client.  OCI charts
# are not added with `helm repo add`; they are addressed directly by URL.
if [[ "$repo_url" == oci://* ]]; then
    helm show chart "$repo_url" >/dev/null
else
    helm repo add "$repo_name" "$repo_url"
fi
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
for true_chart_repo_name in "${truecharts_apps[@]}"; do
    add_rancher_repo "truecharts-$true_chart_repo_name" "oci://oci.trueforge.org/truecharts/$true_chart_repo_name"
done

add_rancher_repo "zabbix-community" "https://zabbix-community.github.io/helm-zabbix" # https://github.com/zabbix-community/helm-zabbix.git
add_rancher_repo "docker-mailserver" "https://docker-mailserver.github.io/docker-mailserver-helm/" # https://github.com/docker-mailserver/docker-mailserver-helm.git
add_rancher_repo "elastic" "https://helm.elastic.co" # https://github.com/elastic/cloud-on-k8s/tree/main/deploy/eck-stack/charts
#add_rancher_repo "bitnamicharts-postgresql" "oci://registry-1.docker.io/bitnamicharts/postgresql" # https://github.com/bitnami/charts
add_rancher_repo "mlohr-roundcube" "https://helm-charts.mlohr.com/" # https://gitlab.com/MatthiasLohr/roundcube-helm-chart
add_rancher_repo "cloudnative-pg" "https://cloudnative-pg.github.io/charts" # https://github.com/cloudnative-pg/charts
add_rancher_repo "cloudcasa-vendor" "https://catalogicsoftware.github.io/cloudcasa-helmchart"
add_rancher_repo "node-feature-discovery" "https://kubernetes-sigs.github.io/node-feature-discovery/charts" # https://github.com/kubernetes-sigs/node-feature-discovery
add_rancher_repo "intel" "https://intel.github.io/helm-charts/"
add_rancher_repo "media-servarr" "https://media-servarr.shw.al/charts"

# Refresh the locally configured HTTP repositories after all additions.
helm repo update


# TODO meshcommander
# TODO shinobi
# TODO youtubedl-material
# TODO node-feature-discovery 	intel-device-plugins-operator 	intel-device-plugins-gpu 
