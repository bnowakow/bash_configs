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
        echo $(/etc/zabbix/zabbix_agent2.d/bash_configs/rancher/zabbix/lib/helm-search-for-exact-chart.sh $name | awk '{print $2}' | head -n1)
        exit
    fi
else
    # there is a repo on disk, so we'll be checking it
    cd $chart_repo_dir
    #git reset --hard 2>/dev/null >/dev/null 
    #git clean -f -d -x 2>/dev/null >/dev/null
    #git pull 2>/dev/null >/dev/null # &
    #if [ $? -gt 0 ]; then 
    #    echo false,git-pull-fail; 
    #fi
    # TODO check git status -uno if branch is not behind origin, downside would be if it takes too long

    file_path=Chart.yaml
    if [ -f $file_path ]; then 
        echo $(grep ^version $file_path | sed 's/.*: //' | sed 's/\ .*//')
        exit
    fi

    if ls *.tgz > /dev/null 2>&1; then
        latest_tarbal=$(ls -1 *tgz | tail -1)
        # TODO | sed 's/.*: //' | sed 's/\ .*//' part is repeated with above
        tar -Oxvf $latest_tarbal $name/Chart.yaml 2> /dev/null | grep  ^version | sed 's/.*: //' | sed 's/\ .*//'
        exit
    fi
fi

exit 1

