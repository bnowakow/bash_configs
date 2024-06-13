#!/bin/bash -x

# kubectl get pods --show-labels

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
kubectl --namespace default port-forward $POD_NAME $external_port:$CONTAINER_PORT --address='0.0.0.0' 
#&#

