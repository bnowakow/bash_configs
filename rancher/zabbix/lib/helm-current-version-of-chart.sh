#!/bin/bash

name="${1:-duckdns}"

chart_repo_dir=$(/etc/zabbix/zabbix_agent2.d/bash_configs/rancher/zabbix/lib/helm-chart-repo-dir.sh $name) 

cd $chart_repo_dir
#git reset --hard 2>/dev/null >/dev/null 
#git clean -f -d -x 2>/dev/null >/dev/null
#git pull 2>/dev/null >/dev/null # &
#if [ $? -gt 0 ]; then 
#    echo false,git-pull-fail; 
#fi
# TODO check git status -uno if branch is not behind origin, downside would be if it takes too long
version_current=$(grep ^version Chart.yaml | sed 's/.*: //')
echo $version_current

