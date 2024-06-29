#!/bin/bash

list_of_non_system_apps=$(sudo /bin/helm ls --all-namespaces --kubeconfig /etc/rancher/k3s/k3s.yaml | grep -v 'cattle-' | grep -v 'kube-system' | grep -v 'cert-manager' | grep -v 'NAME' | awk '{print $1}')

for app in $list_of_non_system_apps; do
    echo "checking if $app has an update version in repo (bnowakow branch must be merged with master, pushed and refreshed in rancher to be availible)";
    # TODO this wouldn't work for zabbix since it's not from trucharts repo
    if ./zabbix/is-helm-image-up-to-date.sh $app; then
        echo "\tno update availible, current version is up to date";
    else
        echo "\tupdate is availible"
        current_version=$(./zabbix/lib/helm-current-version-of-chart.sh $app)
        namespace=$(sudo /bin/helm ls --all-namespaces --kubeconfig /etc/rancher/k3s/k3s.yaml | grep $app | awk '{print $2}')
        chart_repo_dir=$(/etc/zabbix/zabbix_agent2.d/bash_configs/rancher/zabbix/lib/helm-chart-repo-dir.sh $app)
        rm -f values.yaml
        sudo kubectl get deploy -n $namespace $app -o yaml --kubeconfig /etc/rancher/k3s/k3s.yaml > values.yaml
        sudo helm upgrade --kubeconfig /etc/rancher/k3s/k3s.yaml --history-max=5 --install=true --namespace=$namespace --timeout=10m0s --values=values.yaml --version=$current_version --wait=true $app $chart_repo_dir | head -n3
        rm values.yaml
    fi
done

