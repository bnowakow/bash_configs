#!/bin/bash

name=plex

pod_params=$(sudo k3s kubectl get pods --all-namespaces -o wide | grep $name)

pod_namespace=$(echo $pod_params | awk '{print $1}')
pod_name=$(echo $pod_params | awk '{print $2}')
pod_ip=$(sudo k3s kubectl describe pod $pod_name -n $pod_namespace | egrep '^IP:' | awk '{print $2}')
pod_health_check_script_path=$(sudo k3s kubectl describe pod $pod_name -n $pod_namespace | grep Liveness | awk '{print $3}' | sed 's/^.//' | sed 's/.$//')

#echo describe pod
#sudo k3s kubectl describe pod $pod_name -n $pod_namespace | less
#echo

#echo console inside pod
#sudo k3s kubectl exec -n $pod_namespace -it $pod_name -- bash

#echo health check script
#sudo k3s kubectl exec -n $pod_namespace -it $pod_name -- cat $pod_health_check_script_patch
#echo

#echo run health check script inside pod
#sudo k3s kubectl exec -n $pod_namespace -it $pod_name -- bash -c "time $pod_health_check_script_path; echo $?"
#echo

echo manual health check from host
time curl -ksf http://$pod_ip:32400/identity; echo $?
echo

echo show system events
sudo k3s kubectl get events
echo

echo show namespace events
sudo k3s kubectl get events --namespace=$pod_namespace
echo

#echo current logs
#sudo k3s kubectl logs $pod_name --namespace=$pod_namespace
#echo

#echo previous logs
#sudo k3s kubectl logs $pod_name --namespace=$pod_namespace --previous
#echo

