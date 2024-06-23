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
# TODO for external-service we run multiple of the same helm but we check version of only first one
version_local=$(sudo /bin/helm ls --all-namespaces --kubeconfig /etc/rancher/k3s/k3s.yaml | grep $name- | head -1 | awk '{print $9}')
# https://www.truenas.com/community/threads/install-helm-chart-via-command-line.97191/
# https://github.com/k3s-io/k3s/issues/1126
if sudo /bin/helm ls --all-namespaces --kubeconfig /etc/rancher/k3s/k3s.yaml | grep $name | awk '{print $9}' | sed 's/.*-//' | grep $version_current > /dev/null; then
    echo true;
else
    # below is to address 1.9 vs 1.19 where string comparison needs 001.009 vs 001.019
    numerical_version_current=""
    for i in $(echo $version_current | sed 's/.*-//' | tr '.' ' '); do
        numerical_version_current=$numerical_version_current.$(printf "%03d" $i);
    done
    numerical_version_local=""
    for i in $(echo $version_local | sed 's/.*-//' | tr '.' ' '); do
        numerical_version_local=$numerical_version_local.$(printf "%03d" $i);
    done
    if [ "$numerical_version_local" = "" ]; then
        echo "false,not-running"
        # https://discord.com/channels/830763548678291466/1051965552458993787/1052262549132935218
        # in case of "Error: UPGRADE FAILED: another operation (install/upgrade/rollback) is in progress"
        # 1: sudo k3s kubectl describe deploy -n ix-$NAME | grep helm-revision
        # 2: sudo k3s kubectl get secrets -n ix-$NAME
        # for every number in #2 that's higer than #1 do:
        # sudo k3s kubectl delete secret -n ix-$NAME sh.helm.release.v1.$NAME.v$NUMBER
        # Stop the app
        # Start the app
        # Edit the app and save without changes
        # If all works, try to upgrade. If not. reinstall.
        exit
    fi
    if [ $(echo -e "$numerical_version_local\n$numerical_version_current" | sort | tail -1) = $numerical_version_local ]; then
        # local version is greater than current (repo is not keeping up with updates in helm)
        echo "true,newer";
    else
        echo false,$version_local,$version_current;
    fi
fi

