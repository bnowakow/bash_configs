#!/bin/bash -x

list_of_non_system_apps=$(sudo /bin/helm ls --all-namespaces --kubeconfig /etc/rancher/k3s/k3s.yaml | grep -v 'cattle-' | grep -v 'kube-system' | grep -v 'cert-manager' | grep -v 'NAME' | awk '{print $1}')

for app in $list_of_non_system_apps; do
    echo "checking if $app has an update version in repo (bnowakow branch must be merged with master, pushed and refreshed in rancher to be availible)";
    # TODO this wouldn't work for zabbix since it's not from trucharts repo
    if ./zabbix/is-helm-image-up-to-date.sh $app; then
        echo "\tno update availible, current version is up to date";
    else
        echo "\tupdate is availible"
        ./zabbix/lib/helm-current-version-of-chart.sh $app
        exit        
    fi
done

