#!/bin/bash 

sudo su zabbix -c "/home/sup/code/bash_configs/rancher/cron/git-pull.sh"
helm repo update

list_of_non_system_apps=$(/bin/helm ls --all-namespaces --kubeconfig /etc/rancher/k3s/k3s.yaml | grep -v 'cattle-' | grep -v 'kube-system' | grep -v 'cert-manager' | grep -v 'NAME' | awk '{print $1}')

for app in $list_of_non_system_apps; do
    # (bnowakow branch must be merged with master, pushed and refreshed in rancher to be availible)";
    echo "checking if $app has an update version in repo"
    echo -e -n "\t"
    if ./zabbix/is-helm-image-up-to-date.sh $app --do-not-update-helm; then
        echo -e "\tno update availible, current version is up to date";
    else
        echo -e "\tupdate is availible"
        current_version=$(./zabbix/lib/helm-current-version-of-chart.sh $app --do-not-update-helm)
        # didn't work for postgresql
        #namespace=$(/bin/helm ls --all-namespaces --kubeconfig /etc/rancher/k3s/k3s.yaml | grep [^-]$app | awk '{print $2}')
        namespace=$(/bin/helm ls --all-namespaces --kubeconfig /etc/rancher/k3s/k3s.yaml | grep "^$app\ " | awk '{print $2}')
        chart_repo_dir_or_helm_repo=$(/etc/zabbix/zabbix_agent2.d/bash_configs/rancher/zabbix/lib/helm-chart-repo-dir-or-helm-repo.sh $app)
        rm -f values.yaml
        # below fails for postgresql and prometheus-operator since it doesn't have deployments, but it rancher it shows something :/
        #sudo kubectl get deploy -n $namespace $app -o yaml --kubeconfig /etc/rancher/k3s/k3s.yaml > values.yaml
        echo -e "\t"would you like to update y/N
        read line;
        if [ "$line" == "y" ]; then
            echo -e "\t"updating
            # TODO below will that fail with helm repo that will have empty $chart_repo_dir_or_helm_repo, check if all arguments are not empty
            #sudo helm upgrade --kubeconfig /etc/rancher/k3s/k3s.yaml --history-max=5 --install=true --namespace=$namespace --timeout=10m0s --values=values.yaml --version=$current_version --wait=true $app $chart_repo_dir_or_helm_repo | head -n3
            sudo helm upgrade --kubeconfig /etc/rancher/k3s/k3s.yaml --history-max=5 --install=true --namespace=$namespace --timeout=10m0s --version=$current_version --wait=true $app $chart_repo_dir_or_helm_repo | head -n3
            # for prometheus-operator additional helm dependency build was needed
	    #rm values.yaml
            #mv values.yaml values-$app.yaml
        else
            echo "\t"skipping update
        fi
    fi
    echo
done

