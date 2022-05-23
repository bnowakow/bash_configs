#!/bin/bash

# https://stackoverflow.com/a/20983251
green=`tput setaf 2`
reset=`tput sgr0`

name=plex

pod_params=$(sudo k3s kubectl get pods --all-namespaces -o wide | grep $name)

pod_namespace=$(echo $pod_params | awk '{print $1}')
pod_name=$(echo $pod_params | awk '{print $2}')
pod_ip=$(sudo k3s kubectl describe pod $pod_name -n $pod_namespace | egrep '^IP:' | awk '{print $2}')
pod_health_check_script_path=$(sudo k3s kubectl describe pod $pod_name -n $pod_namespace | grep 'Liveness:' | awk '{print $3}' | sed 's/^.//' | sed 's/.$//')

#echo "${green}describe pod${reset}"
#sudo k3s kubectl describe pod $pod_name -n $pod_namespace | less

#echo "${green}console inside pod${reset}"
#sudo k3s kubectl exec -n $pod_namespace -it $pod_name -- bash

#echo "${green}health check script${reset}"
#sudo k3s kubectl exec -n $pod_namespace -it $pod_name -- cat $pod_health_check_script_patch
#echo

#echo "${green}run health check script inside pod${reset}"
#sudo k3s kubectl exec -n $pod_namespace -it $pod_name -- bash -c "time $pod_health_check_script_path; echo $?"
#echo

echo "${green}free memory${reset}"
free -h | head -n2
echo

echo "${green}inode-nr${reset}"
cat /proc/sys/fs/inode-nr
echo

echo "${green}manual health check from host${reset}"
time curl -ksf http://$pod_ip:32400/identity; echo $?
echo

#echo "${green}show system events${reset}"
#sudo k3s kubectl get events
#echo

#echo "${green}show namespace events${reset}"
#sudo k3s kubectl get events --namespace=$pod_namespace
#echo

echo "${green}show pod events from describe${reset}"
describe_events_grep_line_mumber=$(sudo k3s kubectl describe pod $pod_name -n $pod_namespace | grep -n Events | cut -d : -f 1)
describe_total_line_length=$(sudo k3s kubectl describe pod $pod_name -n $pod_namespace | wc -l)
number_to_tail=$(($describe_total_line_length-$describe_events_grep_line_mumber+1))
sudo k3s kubectl describe pod $pod_name -n $pod_namespace | tail -n $number_to_tail
echo

#echo "${green}current logs${reset}"
#sudo k3s kubectl logs $pod_name --namespace=$pod_namespace
#echo

#echo "${green}previous logs${reset}"
#sudo k3s kubectl logs $pod_name --namespace=$pod_namespace --previous
#echo

