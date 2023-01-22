#!/bin/bash

name="${1:-duckdns}"

#helm repo add TrueCharts https://charts.truecharts.org > /dev/null
#helm repo update > /dev/null

#helm pull TrueCharts/duckdns

charts_repo_dir=/etc/zabbix/zabbix_agent2.d/bash_configs/charts-repo
charts_repo_truenas_name=truenas
charts_repo_truecharts_name=truecharts
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

if [ $name = "plex" ]; then 
    clone_repo_if_doesnt_exist $charts_repo_truenas_name
    cd $charts_repo_truenas_name/charts/plex/
    cd $(ls -d */)
else
    if [ $name = "zabbix" ]; then
        train="incubator";
    else
        train="stable";
    fi
    # below works well but TrueNas probably using Charts directly from repo
    #version_current=$(helm search repo TrueCharts/$name --versions | head -2 | tail -1 | awk '{print $2}')
    clone_repo_if_doesnt_exist $charts_repo_truecharts_name
    cd $charts_repo_truecharts_name/charts/$train/$name
fi

git pull 2>/dev/null >/dev/null
version_current=$(grep ^version Chart.yaml | sed 's/.*: //')
version_local=$(sudo /bin/helm ls --all-namespaces --kubeconfig /etc/rancher/k3s/k3s.yaml | grep $name | awk '{print $9}')

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
    if [ $(echo -e "$numerical_version_local\n$numerical_version_current" | sort | tail -1) = $numerical_version_local ]; then
        # local version is greater than current (repo is not keeping up with updates in helm)
        echo "true,newer";
    else
        echo false,$version_local,$version_current;
    fi
fi

