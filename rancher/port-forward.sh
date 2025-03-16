#!/bin/bash -x

# kubectl get pods --show-labels

external_port=32400
port_number=0
item_number=0
namespace="apps-plex"
POD_NAME=$(kubectl get pods --namespace $namespace -l "app.kubernetes.io/instance=plex" -o jsonpath="{.items[$item_number].metadata.name}")
#POD_NAME=plex
CONTAINER_PORT=$(kubectl get pod --namespace $namespace $POD_NAME -o jsonpath="{.spec.containers[0].ports[$port_number].containerPort}")
#CONTAINER_PORT=$external_port
kubectl --namespace $namespace port-forward $POD_NAME $external_port:$CONTAINER_PORT --address='0.0.0.0' &

exit

external_port=9090
item_number=0
app_name="calibre"
namespace="apps-$app_name"
POD_NAME=$(kubectl get pods --namespace $namespace -l "app.kubernetes.io/instance=$app_name" -o jsonpath="{.items[$item_number].metadata.name}")
kubectl --namespace $namespace port-forward $POD_NAME $external_port:$external_port --address='0.0.0.0'

exit

external_port=47102
#port_number=0
item_number=0
app_name="scrypted"
namespace="apps-$app_name"
POD_NAME=$(kubectl get pods --namespace $namespace -l "app.kubernetes.io/instance=$app_name" -o jsonpath="{.items[$item_number].metadata.name}")
#CONTAINER_PORT=$(kubectl get pod --namespace $namespace $POD_NAME -o jsonpath="{.spec.containers[0].ports[$port_number].containerPort}")
kubectl --namespace $namespace port-forward $POD_NAME $external_port:$external_port --address='0.0.0.0'

exit

# https://github.com/kubernetes/kubernetes/issues/47862#issuecomment-985168451
# https://krew.sigs.k8s.io/docs/user-guide/setup/install/
external_port=53
port_number=8
item_number=0
app_name="adguard-home"
namespace="apps-$app_name"
describe services -n $namespace $app_name-dns-udp
POD_NAME=$(kubectl get pods --namespace $namespace -l "app.kubernetes.io/instance=$app_name" -o jsonpath="{.items[$item_number].metadata.name}")
CONTAINER_PORT=$(kubectl get pod --namespace $namespace $POD_NAME -o jsonpath="{.spec.containers[0].ports[$port_number].containerPort}")
# https://krew.sigs.k8s.io/docs/user-guide/setup/install/
# https://github.com/knight42/krelay?tab=readme-ov-file#usage
PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH" kubectl krew install relay
PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH" kubectl krew update
PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH" kubectl krew upgrade
PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH" kubectl relay --namespace $namespace $POD_NAME $external_port:$CONTAINER_PORT@udp --address='0.0.0.0' &

exit

external_port=8888
port_number=0
POD_NAME=$(kubectl get pods --namespace default -l "app=zabbix-zabbix-web" -o jsonpath="{.items[0].metadata.name}")
CONTAINER_PORT=$(kubectl get pod --namespace default $POD_NAME -o jsonpath="{.spec.containers[0].ports[$port_number].containerPort}")
echo "Visit http://127.0.0.1:8888 to use your application"
kubectl --namespace default port-forward $POD_NAME $external_port:$CONTAINER_PORT --address='0.0.0.0' &

external_port=8096
port_number=1
POD_NAME=$(kubectl get pods --namespace default -l "app.kubernetes.io/instance=jellyfin" -o jsonpath="{.items[0].metadata.name}")
CONTAINER_PORT=$(kubectl get pod --namespace default $POD_NAME -o jsonpath="{.spec.containers[0].ports[$port_number].containerPort}")
kubectl --namespace default port-forward $POD_NAME $external_port:$CONTAINER_PORT --address='0.0.0.0' &

external_port=8989
port_number=0
item_number=1
POD_NAME=$(kubectl get pods --namespace default -l "app.kubernetes.io/instance=sonarr" -o jsonpath="{.items[$item_number].metadata.name}")
CONTAINER_PORT=$(kubectl get pod --namespace default $POD_NAME -o jsonpath="{.spec.containers[0].ports[$port_number].containerPort}")
kubectl --namespace default port-forward $POD_NAME $external_port:$CONTAINER_PORT --address='0.0.0.0' &

