#!/bin/bash

# https://stackoverflow.com/a/67429065
sudo kubectl get secrets --kubeconfig /etc/rancher/k3s/k3s.yaml --all-namespaces | grep sh.helm.release
echo find which is stucked and then 
echo sudo  kubectl delete secret sh.helm.release.v1.duckdns.v2 --kubeconfig /etc/rancher/k3s/k3s.yaml -n apps-duckdns

