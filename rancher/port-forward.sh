#!/bin/bash -x

# kubectl get pods --show-labels

kubeconfig="/etc/rancher/k3s/k3s.yaml"
kubectl_cmd=(sudo kubectl --kubeconfig "$kubeconfig")

set_pod_name() {
  local namespace="$1"
  local selector="$2"
  local item_number="${3:-0}"

  POD_NAME=$("${kubectl_cmd[@]}" get pods \
    --namespace "$namespace" \
    -l "$selector" \
    -o jsonpath="{range .items[*]}{.metadata.name}{'\n'}{end}" | sed -n "$((item_number + 1))p")

  if [ -z "$POD_NAME" ]; then
    echo "No pod found in namespace '$namespace' with selector '$selector'" >&2
    exit 1
  fi
}

set_container_port() {
  local namespace="$1"
  local pod_name="$2"
  local port_number="$3"

  CONTAINER_PORT=$("${kubectl_cmd[@]}" get pod \
    --namespace "$namespace" \
    "$pod_name" \
    -o jsonpath="{.spec.containers[0].ports[$port_number].containerPort}")

  if [ -z "$CONTAINER_PORT" ]; then
    echo "No container port found for pod '$pod_name' in namespace '$namespace' at index '$port_number'" >&2
    exit 1
  fi
}

port_forward() {
  local namespace="$1"
  local pod_name="$2"
  local external_port="$3"
  local container_port="$4"

  "${kubectl_cmd[@]}" --namespace "$namespace" port-forward "$pod_name" "$external_port:$container_port" --address='0.0.0.0'
}

port_forward_background() {
  port_forward "$@" &
}

# Jellyseerr
external_port=10241
port_number=0
item_number=0
app_name="jellyseerr"
namespace="apps-$app_name"

set_pod_name "$namespace" "app.kubernetes.io/instance=$app_name" "$item_number"
set_container_port "$namespace" "$POD_NAME" "$port_number"
#CONTAINER_PORT=$external_port
port_forward_background "$namespace" "$POD_NAME" "$external_port" "$CONTAINER_PORT"

# BELOW EXPOSES IT TO THE INTERNET

# https://linuxize.com/post/how-to-setup-ssh-tunneling/#remote-port-forwarding

local_port=$external_port

remote_port=$external_port
remote_host=ovh.bnowakowski.pl

ssh -R "$remote_port:127.0.0.1:$local_port" -N -f "$remote_host"
echo $?

exit

# Plex
external_port=32400
port_number=0
item_number=0
app_name="plex"
namespace="apps-$app_name"

set_pod_name "$namespace" "app.kubernetes.io/instance=$app_name" "$item_number"
#POD_NAME=plex
set_container_port "$namespace" "$POD_NAME" "$port_number"
#CONTAINER_PORT=$external_port
port_forward_background "$namespace" "$POD_NAME" "$external_port" "$CONTAINER_PORT"

exit

# Calibre
external_port=9090
item_number=0
app_name="calibre"
namespace="apps-$app_name"

set_pod_name "$namespace" "app.kubernetes.io/instance=$app_name" "$item_number"
port_forward "$namespace" "$POD_NAME" "$external_port" "$external_port"

exit

# Scrypted
external_port=47102
#port_number=0
item_number=0
app_name="scrypted"
namespace="apps-$app_name"

set_pod_name "$namespace" "app.kubernetes.io/instance=$app_name" "$item_number"
# set_container_port "$namespace" "$POD_NAME" "$port_number"
port_forward "$namespace" "$POD_NAME" "$external_port" "$external_port"

exit

# Ad-Guard
# https://github.com/kubernetes/kubernetes/issues/47862#issuecomment-985168451
# https://krew.sigs.k8s.io/docs/user-guide/setup/install/
external_port=53
port_number=8
item_number=0
app_name="adguard-home"
namespace="apps-$app_name"

"${kubectl_cmd[@]}" describe services --namespace "$namespace" "$app_name-dns-udp"
set_pod_name "$namespace" "app.kubernetes.io/instance=$app_name" "$item_number"
set_container_port "$namespace" "$POD_NAME" "$port_number"
# https://krew.sigs.k8s.io/docs/user-guide/setup/install/
# https://github.com/knight42/krelay?tab=readme-ov-file#usage
krew_path="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
PATH="$krew_path" kubectl krew install relay
PATH="$krew_path" kubectl krew update
PATH="$krew_path" kubectl krew upgrade
sudo env "PATH=$krew_path" kubectl --kubeconfig "$kubeconfig" relay \
  --namespace "$namespace" \
  "$POD_NAME" \
  "$external_port:$CONTAINER_PORT@udp" \
  --address='0.0.0.0' &

exit

# Zabbix
external_port=8888
port_number=0
item_number=0
namespace="default"

set_pod_name "$namespace" "app=zabbix-zabbix-web" "$item_number"
set_container_port "$namespace" "$POD_NAME" "$port_number"
echo "Visit http://127.0.0.1:8888 to use your application"
port_forward_background "$namespace" "$POD_NAME" "$external_port" "$CONTAINER_PORT"

# Jellyfin
external_port=8096
port_number=1
item_number=0
app_name="jellyfin"
namespace="default"

set_pod_name "$namespace" "app.kubernetes.io/instance=$app_name" "$item_number"
set_container_port "$namespace" "$POD_NAME" "$port_number"
port_forward_background "$namespace" "$POD_NAME" "$external_port" "$CONTAINER_PORT"

# Sonarr
external_port=8989
port_number=0
item_number=1
app_name="sonarr"
namespace="default"

set_pod_name "$namespace" "app.kubernetes.io/instance=$app_name" "$item_number"
set_container_port "$namespace" "$POD_NAME" "$port_number"
port_forward_background "$namespace" "$POD_NAME" "$external_port" "$CONTAINER_PORT"
