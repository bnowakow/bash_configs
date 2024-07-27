#!/bin/bash

name="${1:-duckdns}"

chart_repo_dir=$(/etc/zabbix/zabbix_agent2.d/bash_configs/rancher/zabbix/lib/helm-chart-repo-dir.sh $name) 

if [ "$chart_repo_dir" == "" ]; then
    # there's no repo on disk, so we'll be checking helm repos
    if helm search repo $name | grep "No results found" > /dev/null; then
        # no results was find in helm repo
        exit 1
    else
        helm repo update > /dev/null
        # return only first result. elasticsearch is present in elastic helm repo and bitnami. adding zz-prefixes to get expected one as first. could be problematic in future
        echo $(/etc/zabbix/zabbix_agent2.d/bash_configs/rancher/zabbix/lib/helm-search-for-exact-chart.sh $name | awk '{print $1}' | head -n1)
        exit
    fi
else
    echo $chart_repo_dir
fi

exit 1

