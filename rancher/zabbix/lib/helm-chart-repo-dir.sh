#!/bin/bash

name="${1:-duckdns}"

#helm repo add TrueCharts https://charts.truecharts.org > /dev/null
#helm repo update > /dev/null

#helm pull TrueCharts/duckdns

charts_repo_dir=/etc/zabbix/zabbix_agent2.d/bash_configs/repos
cd $charts_repo_dir

for repo_dir in $(ls -1); do
    # doing that per directory since then I could set priority of directories when one chart would be in two repos
    # side effect it helps when repo name is same as chart name (i.e. helm with one repo like zabbix)
    if [ $(find $repo_dir -name $name | wc -l) -gt 0 ] ; then
        # TODO that would fail when find returns multiple results (i.e. common prefix)
        if [ $(find $repo_dir -name Chart.yaml | grep -E "\/$name/Chart.yaml" | wc -l) -gt 0 ]; then
            echo $charts_repo_dir/$(find $repo_dir -name Chart.yaml | grep -E "\/$name/Chart.yaml" | sed 's/\/Chart.yaml$//')
            exit 0
        fi
        if [ $(find $repo_dir -name Chart.yaml | grep -E "\/$name/chart/Chart.yaml" | wc -l) -gt 0 ]; then
            echo $charts_repo_dir/$(find $repo_dir -name Chart.yaml | grep -E "\/$name/chart/Chart.yaml" | sed 's/\/Chart.yaml$//')
            exit 0
        fi
        if [ $(find $repo_dir -name $name*tgz | wc -l) -gt 0 ]; then
            echo $charts_repo_dir/$(find $repo_dir -name $name*tgz | head -n1 | sed "s/\/$name[^\/]*tgz$//" )
            exit 0
        fi
    fi
done

exit 1

