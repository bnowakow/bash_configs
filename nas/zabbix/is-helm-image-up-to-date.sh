#!/bin/bash

helm repo add TrueCharts https://charts.truecharts.org > /dev/null
helm repo update > /dev/null

#helm pull TrueCharts/duckdns

name="${1:-duckdns}"
version_current=$(helm search repo TrueCharts/$name --versions | head -2 | tail -1 | awk '{print $2}')

# https://github.com/k3s-io/k3s/issues/1126
if sudo /bin/helm ls --all-namespaces --kubeconfig /etc/rancher/k3s/k3s.yaml | grep $name | awk '{print $9}' | sed 's/.*-//' | grep $version_current; then
    echo true;
else
    echo false,$(sudo /bin/helm ls --all-namespaces --kubeconfig /etc/rancher/k3s/k3s.yaml | grep $name | awk '{print $9}'),$version_current;
fi

