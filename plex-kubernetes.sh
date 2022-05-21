#!/bin/bash

name=plex

pod_params=$(sudo k3s kubectl get pods --all-namespaces -o wide | grep $name)

pod_namespace=$(echo $pod_params | awk '{print $1}')
pod_name=$(echo $pod_params | awk '{print $2}')
pod_ip=$(sudo k3s kubectl describe pod $pod_name -n $pod_namespace | egrep '^IP:' | awk '{print $2}')
pod_health_check_script_patch=$(sudo k3s kubectl describe pod $pod_name -n $pod_namespace | grep Liveness | awk '{print $3}' | sed 's/^.//' | sed 's/.$//')

# describe pod
#sudo k3s kubectl describe pod $pod_name -n $pod_namespace | less

# console inside pod
#sudo k3s kubectl exec -n $pod_namespace -it $pod_name -- bash

# check health script
#sudo k3s kubectl exec -n $pod_namespace -it $pod_name -- cat $pod_health_check_script_patch

# health check script
sudo k3s kubectl exec -n $pod_namespace -it $pod_name -- bash -c "$pod_health_check_script_patch; echo $?"


