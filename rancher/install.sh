#!/bin/bash

# TODO check if root

# https://stackoverflow.com/a/65755417
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# https://docs.k3s.io/installation/uninstall
#/usr/local/bin/k3s-uninstall.sh

# https://ranchermanager.docs.rancher.com/how-to-guides/new-user-guides/kubernetes-cluster-setup/k3s-for-rancher
# https://www.suse.com/suse-rancher/support-matrix/all-supported-versions/rancher-v2-11-4/
# https://github.com/k3s-io/k3s/releases/tag/v1.32.7%2Bk3s1

# first node
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.32.6%2Bk3s1" sh -s - server
# TODO currently installed without datastore: sh -s - server --datastore-endpoint="<DATASTORE_ENDPOINT>"
cp /home/sup/code/bash_configs/rancher/config.yaml /etc/rancher/k3s/config.yaml 
chmod 644 /etc/rancher/k3s/config.yaml
systemctl stop k3s
systemctl start k3s

# next nodes
first_node_host=proxmox3.tailscale.bnowakowski.pl
k3s_token=$(ssh sup@$first_node_host "sudo -S cat /var/lib/rancher/k3s/server/node-token")
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.32.6%2Bk3s1" sh -s - server --server https://$first_node_host:6443 --token $k3s_token

# https://cert-manager.io/v1.0-docs/usage/kubectl-plugin/
# not every cert-manager release contains cli tool
# https://github.com/cert-manager/cert-manager/releases/tag/v1.14.7
curl -L -o kubectl-cert-manager.tar.gz https://github.com/cert-manager/cert-manager/releases/download/v1.14.7/kubectl-cert_manager-linux-amd64.tar.gz
tar xzf kubectl-cert-manager.tar.gz
sudo mv kubectl-cert_manager /usr/local/bin
rm kubectl-cert-manager.tar.gz

# https://ranchermanager.docs.rancher.com/getting-started/installation-and-upgrade/install-upgrade-on-a-kubernetes-cluster#kubernetes-cluster
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo add jetstack https://charts.jetstack.io
helm repo update
# https://github.com/cert-manager/cert-manager/releases
# https://github.com/rancher/rancher/issues/26850#issuecomment-1223301973
# https://github.com/rancher/rancher/issues/26850#issuecomment-1234869006
# replace `helm upgrade` with `helm install` on first try
kubectl get pods --namespace cert-manager
helm upgrade cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.18.2 --set startupapicheck.timeout=5m --set crds.enabled=true
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.18.2/cert-manager.crds.yaml
kubectl get pods --namespace cert-manager
# https://cert-manager.io/docs/configuration/
# https://cert-manager.io/docs/troubleshooting/acme/#2-troubleshooting-orders
helm install rancher rancher-stable/rancher --namespace cattle-system --create-namespace --set hostname=$(hostname).tailscale.bnowakowski.pl --set bootstrapPassword=admin --set ingress.tls.source=letsEncrypt --set letsEncrypt.email=dobrowolski.nowakowski@gmail.com
./cert-manager/install.sh
# to check status of above helm install
kubectl -n cattle-system rollout status deploy/rancher
kubectl -n cattle-system get deploy rancher
echo https://$(hostname).tailscale.bnowakowski.pl/dashboard/?setup=$(kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}')

./rancher_add_cluster_repos.sh

# below uses DNS01 challenge since rancher isn't reachable from the internet
helm upgrade rancher rancher-stable/rancher --namespace cattle-system --set hostname=$(hostname).tailscale.bnowakowski.pl --set bootstrapPassword=admin --set ingress.tls.source=secret --set ingress.extraAnnotations.'cert-manager\.io/cluster-issuer'=letsencrypt
kubectl cert-manager renew -A --all 
kubectl cert-manager renew tls-rancher-ingress -n cattle-system
# https://ranchermanager.docs.rancher.com/getting-started/installation-and-upgrade/install-upgrade-on-a-kubernetes-cluster/troubleshooting
kubectl -n cattle-system describe ingress

kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundle.yaml

echo https://catalogicsoftware.github.io/cloudcasa-helmchart
echo https://github.com/bnowakow/truecharts-charts.git
echo https://prometheus-community.github.io/helm-charts

echo on restore of shinobi:
echo 1. create pv, create pvc
echo 2. restore shinobi without pvc being overriden

