#!/bin/bash

# https://stackoverflow.com/a/5947802
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

sudo su zabbix -c "/home/sup/code/bash_configs/rancher/cron/git-pull.sh"
helm repo update

list_of_non_system_apps=$(/bin/helm ls --all-namespaces --kubeconfig /etc/rancher/k3s/k3s.yaml | grep -v 'cattle-' | grep -v 'kube-system' | grep -v 'cert-manager' | grep -v 'NAME' | grep -v 'cloudnative-pg' | grep -v 'longhorn-crd' | grep -v 'shinobi' | grep -v 'intel-device-plugins-operator' | grep -v 'node-feature-discovery' | grep -v 'meshcommander' | grep -v 'plex' | awk '{print $1}')

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
        # below assumes that each application is run in separate namespace! 
        # TODO this is not true eg. for apps-postgresql where it has pgadmin and postgresql
        if kubectl get ingress -n $namespace 2>&1 | grep -q "No resources found"; then
            ingress_exist=0;
        else
            ingress_exist=1;
        fi
        echo -e "\tingress_exist=$ingress_exist"
        if [ "$ingress_exist" == "1" ]; then
            url=$(kubectl get ingress -n $namespace |awk '{print $3 }' | tail -1 | sed -e 's/,.*//')
            http_code=$(curl -L -s -o /dev/null -w "%{http_code}" "https://$url/")
            if [ "$http_code" != 200 ]; then
                echo -e "\t${RED}http-code=$http_code${NC} url=$url"
                echo -e "${RED}non-200 http-code${NC}";
                exit
            else
                echo -e "\t${GREEN}http-code=$http_code${NC} url=$url"
            fi
            http_code="before-update"
        else
            # TODO if ingress doesn't exist check healthcheck?
            echo -e "\tno ingress, healthcheck not yet checked"
        fi
        echo -e "\t"would you like to update y/N
        read line;
        if [ "$line" == "y" ]; then
            echo -e "\t"updating
            # TODO below will that fail with helm repo that will have empty $chart_repo_dir_or_helm_repo, check if all arguments are not empty
            #sudo helm upgrade --kubeconfig /etc/rancher/k3s/k3s.yaml --history-max=5 --install=true --namespace=$namespace --timeout=10m0s --values=values.yaml --version=$current_version --wait=true $app $chart_repo_dir_or_helm_repo | head -n3

            #sudo helm template --kubeconfig /etc/rancher/k3s/k3s.yaml --namespace=$namespace --timeout=10m0s --version=$current_version --wait=true $app $chart_repo_dir_or_helm_repo 
            sudo helm upgrade --kubeconfig /etc/rancher/k3s/k3s.yaml --history-max=5 --install=true --namespace=$namespace --timeout=10m0s --version=$current_version --wait=true $app $chart_repo_dir_or_helm_repo | head -n3
            # for prometheus-operator additional helm dependency build was needed
	    #rm values.yaml
            #mv values.yaml values-$app.yaml
            if [ "$ingress_exist" == "1" ]; then
                http_code=$(curl -L -s -o /dev/null -w "%{http_code}" "https://$url/")
                if [ "$http_code" != 200 ]; then
                    echo -e "\t${RED}http-code-after-update=$http_code${NC}"
                    exit
                else
                    echo -e "\t${GREEN}http-code-after-update=$http_code${NC}"
                fi
                http_code="after-update"
            fi
        else
            echo "\t"skipping update
        fi
    fi
    echo
done

