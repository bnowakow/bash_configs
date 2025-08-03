#!/bin/bash

# TODO check if root

# /usr/local/bin/rke2-uninstall.sh
# https://docs.rke2.io/install/quickstart
curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION="v1.32.6+rke2r1" sh -
systemctl enable rke2-server.service
systemctl start rke2-server.service
journalctl -u rke2-server -f



# https://stackoverflow.com/a/65755417
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# https://docs.k3s.io/installation/uninstall
#/usr/local/bin/k3s-uninstall.sh

# https://ranchermanager.docs.rancher.com/how-to-guides/new-user-guides/kubernetes-cluster-setup/k3s-for-rancher
# https://www.suse.com/suse-rancher/support-matrix/all-supported-versions/rancher-v2-11-4/
# https://github.com/k3s-io/k3s/releases/tag/v1.32.7%2Bk3s1

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.32.6%2Bk3s1" sh -s - server

# args that failed: sh -s - server --datastore-endpoint="<DATASTORE_ENDPOINT>"

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.32.6%2Bk3s1" sh -s - server --token "$(cat /var/lib/rancher/k3s/server/token)"

# https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
##curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
##install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
apt-get update
apt-get install -y apt-transport-https ca-certificates curl
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list   # helps tools such as command-not-found to work correctly
sudo apt-get update
sudo apt-get install -y kubectl

# https://cert-manager.io/v1.0-docs/usage/kubectl-plugin/
# not every cert-manager release contains cli tool
# https://github.com/cert-manager/cert-manager/releases/tag/v1.15.2
curl -L -o kubectl-cert-manager.tar.gz https://github.com/cert-manager/cert-manager/releases/download/v1.14.7/kubectl-cert_manager-linux-amd64.tar.gz
tar xzf kubectl-cert-manager.tar.gz
sudo mv kubectl-cert_manager /usr/local/bin
rm kubectl-cert-manager.tar.gz

# https://helm.sh/docs/intro/install/
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
sudo apt-get install apt-transport-https --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install -y helm

# https://ranchermanager.docs.rancher.com/getting-started/installation-and-upgrade/install-upgrade-on-a-kubernetes-cluster#kubernetes-cluster
# https://github.com/cert-manager/cert-manager/releases/tag/v1.16.2
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update
#kubectl delete namespace cattle-system
helm repo add jetstack https://charts.jetstack.io
helm repo update
# https://github.com/cert-manager/cert-manager/releases
# https://github.com/rancher/rancher/issues/26850#issuecomment-1223301973
# https://github.com/rancher/rancher/issues/26850#issuecomment-1234869006
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.2 --set startupapicheck.timeout=5m --set crds.enabled=true
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.16.2/cert-manager.crds.yaml
kubectl get pods --namespace cert-manager
helm upgrade cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.18.2 --set startupapicheck.timeout=5m --set crds.enabled=true
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.18.2/cert-manager.crds.yaml
kubectl get pods --namespace cert-manager
# https://cert-manager.io/docs/configuration/
# https://cert-manager.io/docs/troubleshooting/acme/#2-troubleshooting-orders
# latest was used when only rancher 2.9 had oci support and it wasn't in stable
helm install rancher rancher-stable/rancher --namespace cattle-system --create-namespace --set hostname=$(hostname).tailscale.bnowakowski.pl --set bootstrapPassword=admin --set ingress.tls.source=letsEncrypt --set letsEncrypt.email=dobrowolski.nowakowski@gmail.com
./cert-manager/install.sh
# to check status of above helm install
kubectl -n cattle-system rollout status deploy/rancher
kubectl -n cattle-system get deploy rancher
echo https://$(hostname).tailscale.bnowakowski.pl/dashboard/?setup=$(kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}')

# below works only for http challenge, when rancher isn't reachable from internet we need to use method below it which uses existing DNS challenge configured
## https://github.com/rancher/rancher/issues/32206#issuecomment-1555969372
# used previously, don't use now: #helm upgrade rancher rancher-stable/rancher --namespace cattle-system --set hostname=$(hostname).tailscale.bnowakowski.pl --set bootstrapPassword=admin --set ingress.tls.source=letsEncrypt --set letsEncrypt.email=dobrowolski.nowakowski@gmail.com
## https://gist.github.com/dmancloud/0474dbfedaa7e3793099f68e96cab88f
# used previously, don't use now: #helm upgrade rancher rancher-stable/rancher --namespace cattle-system --set hostname=$(hostname).tailscale.bnowakowski.pl --set bootstrapPassword=admin --set ingress.tls.source=letsEncrypt --set letsEncrypt.email=dobrowolski.nowakowski@gmail.com --set letsEncrypt.ingress.class=traefik

# below uses DNS01 challenge since rancher isn't reachable from the internet
# latest was used when only rancher 2.9 had oci support and it wasn't in stable
# currently installed v2.10.1
helm upgrade rancher rancher-stable/rancher --namespace cattle-system --set hostname=$(hostname).tailscale.bnowakowski.pl --set bootstrapPassword=admin --set ingress.tls.source=secret --set ingress.extraAnnotations.'cert-manager\.io/cluster-issuer'=letsencrypt
kubectl cert-manager renew -A --all 
kubectl cert-manager renew tls-rancher-ingress -n cattle-system
# https://ranchermanager.docs.rancher.com/getting-started/installation-and-upgrade/install-upgrade-on-a-kubernetes-cluster/troubleshooting
kubectl -n cattle-system describe ingress

# https://github.com/harvester/harvester/issues/7489
# TODO replace token to get from secret or other wayh automatically (have to create cluster first though)
curl -fL https://proxmox3.tailscale.bnowakowski.pl/system-agent-install.sh | CATTLE_AGENT_STRICT_VERIFY=false sh -s - --server https://proxmox3.tailscale.bnowakowski.pl --label 'cattle.io/os=linux' --token TODO_REPLACE_TOKEN --etcd --controlplane --worker

kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundle.yaml

kubectl create namespace longhorn-system
# https://longhorn.io/docs/1.8.1/deploy/install/#installing-open-iscsi
modprobe iscsi_tcp
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.8.1/deploy/prerequisite/longhorn-iscsi-installation.yaml
# check status of above
kubectl -n longhorn-system get pod | grep longhorn-iscsi-installation
# TODO take id from above
kubectl -n longhorn-system logs longhorn-iscsi-installation-pzb7r -c iscsi-installation
# https://longhorn.io/docs/1.8.1/deploy/install/#installing-nfsv4-client
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.8.1/deploy/prerequisite/longhorn-nfs-installation.yaml
# check status of above
kubectl -n longhorn-system get pod | grep longhorn-nfs-installation
# TODO take id from above
kubectl -n longhorn-system logs longhorn-nfs-installation-t2v9v -c nfs-installation
# https://longhorn.io/docs/1.8.1/deploy/install/#installing-open-iscsi
apt-get install cryptsetup
modprobe dm_crypt
# https://longhorn.io/docs/1.8.1/deploy/install/#using-the-environment-check-script
curl -sSfL https://raw.githubusercontent.com/longhorn/longhorn/v1.8.1/scripts/environment_check.sh | bash
# https://longhorn.io/docs/1.8.1/deploy/install/#using-the-longhorn-command-line-tool
curl -sSfL -o longhornctl https://github.com/longhorn/cli/releases/download/v1.8.1/longhornctl-linux-amd64
chmod +x longhornctl
./longhornctl check preflight
./longhornctl install preflight
# https://longhorn.io/docs/1.8.1/nodes-and-volumes/volumes/create-volumes/
kubectl create -f https://raw.githubusercontent.com/longhorn/longhorn/v1.8.1/examples/storageclass.yaml


# for Intel integrated GPU passthrough e.g. for jellyfin transcoding hardware acceleration
# https://jonathangazeley.com/2025/02/11/intel-gpu-acceleration-on-kubernetes/
# https://github.com/kubernetes-sigs/node-feature-discovery
echo https://kubernetes-sigs.github.io/node-feature-discovery/charts
# add above repo to rancher and install node-feature-discovery chart in rancher
kubectl apply -k "https://github.com/kubernetes-sigs/node-feature-discovery/deployment/overlays/default?ref=v0.17.3"
# verify that labes has been added:
kubectl get no $(hostname) -o json | jq .metadata.labels | grep intel
echo https://intel.github.io/helm-charts/
# add above repo to rancher and install intel-device-plugins-operator chart in rancher
# add above repo to rancher and install intel-device-plugins-gpu chart in rancher, make sure that nodeSelector: intel.feature.node.kubernetes.io/gpu: 'true'
# verify:
kubectl get no $(hostname) -o json | jq .status.capacity | grep gpu.intel.com

echo https://github.com/zabbix-community/helm-zabbix.git
#echo https://charts.truecharts.org/
#echo https://github.com/bnowakow/truecharts-charts.git
echo https://github.com/docker-mailserver/docker-mailserver-helm.git
echo https://helm.elastic.co
echo oci://registry-1.docker.io/bitnamicharts/postgresql
echo https://helm-charts.mlohr.com/
echo https://catalogicsoftware.github.io/cloudcasa-helmchart
echo https://github.com/bnowakow/truecharts-charts.git
echo https://cloudnative-pg.github.io/charts
echo https://prometheus-community.github.io/helm-charts

