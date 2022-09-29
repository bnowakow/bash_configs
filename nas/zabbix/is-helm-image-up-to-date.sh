#!/bin/bash

helm repo add TrueCharts https://charts.truecharts.org > /dev/null
helm repo update > /dev/null

#helm pull TrueCharts/duckdns

name="${1:-duckdns}"
if [ $name = "plex" ]; then 
    # TODO fixme workaound since plex is in official helm repo to which I don't have url to search repo
    cd /etc/zabbix/zabbix_agent2.d/bash_configs
    #mkdir tmp-zabbix; 
    cd tmp-zabbix; 
    git clone https://github.com/truenas/charts.git 2> /dev/null 
    cd charts/charts/plex/
    # if below wouldn't be updated check charts/plex/1.7.20/Chart.yaml instead
    version_current=$(ls -d */ | sed 's/\///')
    cd ../../../
    rm -rf charts
    #cd ../../../../
    #rm -rf tmp-zabbix/
else
    version_current=$(helm search repo TrueCharts/$name --versions | head -2 | tail -1 | awk '{print $2}')
fi

# https://github.com/k3s-io/k3s/issues/1126
if sudo /bin/helm ls --all-namespaces --kubeconfig /etc/rancher/k3s/k3s.yaml | grep $name | awk '{print $9}' | sed 's/.*-//' | grep $version_current > /dev/null; then
    echo true;
else
    echo false,$(sudo /bin/helm ls --all-namespaces --kubeconfig /etc/rancher/k3s/k3s.yaml | grep $name | awk '{print $9}'),$version_current;
fi

