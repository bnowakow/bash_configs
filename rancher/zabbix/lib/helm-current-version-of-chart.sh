#!/bin/bash

name="${1:-duckdns}"

#helm repo add TrueCharts https://charts.truecharts.org > /dev/null
#helm repo update > /dev/null

#helm pull TrueCharts/duckdns

charts_repo_dir=/etc/zabbix/zabbix_agent2.d/bash_configs/repos
charts_repo_truecharts_name=truecharts
# TODO that would fail under zabbix user
#mkdir -p $charts_repo_dir
#chown sup:zabbix $charts_repo_dir
# /TODO
cd $charts_repo_dir

clone_repo_if_doesnt_exist() {
    repo_name=$1
    # TODO check if pwd = $charts_repo_dir
    if [ ! -d "$repo_name" ]; then
        git clone https://github.com/$repo_name/charts.git 2> /dev/null;
        mv charts $repo_name;
        cd $repo_name;
        git config pull.rebase false
    fi
}

# todo detect train automatically, via find?
if [ $name = "traefik" ]; then
    train="enterprise";
else
    train="stable";
fi
# below works well but TrueNas probably using Charts directly from repo
#version_current=$(helm search repo TrueCharts/$name --versions | head -2 | tail -1 | awk '{print $2}')
clone_repo_if_doesnt_exist $charts_repo_truecharts_name
cd $charts_repo_truecharts_name/charts/$train/$name
#git reset --hard 2>/dev/null >/dev/null 
#git clean -f -d -x 2>/dev/null >/dev/null
#git pull 2>/dev/null >/dev/null # &
#if [ $? -gt 0 ]; then 
#    echo false,git-pull-fail; 
#fi
# TODO check git status -uno if branch is not behind origin, downside would be if it takes too long
version_current=$(grep ^version Chart.yaml | sed 's/.*: //')
echo $version_current

