#!/bin/bash

# TODO check if root

# https://docs.k3s.io/installation/uninstall
#/usr/local/bin/k3s-uninstall.sh

# https://ranchermanager.docs.rancher.com/how-to-guides/new-user-guides/kubernetes-cluster-setup/k3s-for-rancher
# https://www.suse.com/suse-rancher/support-matrix/all-supported-versions/rancher-v2-8-5/
# https://github.com/k3s-io/k3s/releases/tag/v1.30.3%2Bk3s1

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.30.3+k3s1" sh -s - server 

# args that failed: sh -s - server --datastore-endpoint="<DATASTORE_ENDPOINT>"

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.30.3+k3s1" sh -s - server --token "$(cat /var/lib/rancher/k3s/server/token)"

# https://stackoverflow.com/a/65755417
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

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
# https://github.com/cert-manager/cert-manager/releases/tag/v1.14.5
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update
#kubectl delete namespace cattle-system
kubectl create namespace cattle-system
helm repo add jetstack https://charts.jetstack.io
helm repo update
# https://github.com/cert-manager/cert-manager/releases
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.15.2 --set startupapicheck.timeout=5m --set crds.enabled=true
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.15.2/cert-manager.crds.yaml
kubectl get pods --namespace cert-manager
# https://cert-manager.io/docs/configuration/
# https://cert-manager.io/docs/troubleshooting/acme/#2-troubleshooting-orders
helm install rancher rancher-stable/rancher --namespace cattle-system --set hostname=proxmox3.localdomain.bnowakowski.pl --set bootstrapPassword=admin
kubectl -n cattle-system rollout status deploy/rancher # to check status of above
kubectl -n cattle-system get deploy rancher
echo https://proxmox3.localdomain.bnowakowski.pl/dashboard/?setup=$(kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}')

# below works only for http challenge, when rancher isn't reachable from internet we need to use method below it which uses existing DNS challenge configured
## https://github.com/rancher/rancher/issues/32206#issuecomment-1555969372
#helm upgrade rancher rancher-stable/rancher --namespace cattle-system --set hostname=proxmox3.localdomain.bnowakowski.pl --set bootstrapPassword=admin --set ingress.tls.source=letsEncrypt --set letsEncrypt.email=dobrowolski.nowakowski@gmail.com
## https://gist.github.com/dmancloud/0474dbfedaa7e3793099f68e96cab88f
#helm upgrade rancher rancher-stable/rancher --namespace cattle-system --set hostname=proxmox3.localdomain.bnowakowski.pl --set bootstrapPassword=admin --set ingress.tls.source=letsEncrypt --set letsEncrypt.email=dobrowolski.nowakowski@gmail.com --set letsEncrypt.ingress.class=traefik

# https://github.com/rancher/rancher/issues/26850#issuecomment-1223301973
# https://github.com/rancher/rancher/issues/26850#issuecomment-1234869006
helm repo update
helm upgrade cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version v1.15.2 --set startupapicheck.timeout=5m --set crds.enabled=true
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.15.2/cert-manager.crds.yaml
# until 2.9 isn't in stable we'll be using latest instead 
#helm upgrade rancher rancher-stable/rancher --namespace cattle-system --set hostname=proxmox3.localdomain.bnowakowski.pl --set bootstrapPassword=admin --set ingress.tls.source=secret --set ingress.extraAnnotations.'cert-manager\.io/cluster-issuer'=letsencrypt
helm upgrade rancher rancher-latest/rancher --namespace cattle-system --set hostname=proxmox3.localdomain.bnowakowski.pl --set bootstrapPassword=admin --set ingress.tls.source=secret --set ingress.extraAnnotations.'cert-manager\.io/cluster-issuer'=letsencrypt
kubectl cert-manager renew -A --all 
kubectl cert-manager renew tls-rancher-ingress -n cattle-system

echo https://github.com/zabbix-community/helm-zabbix.git
#echo https://charts.truecharts.org/
echo https://github.com/bnowakow/truecharts-charts.git


