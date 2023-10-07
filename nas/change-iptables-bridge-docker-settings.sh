#!/bin/bash

# TODO fix regexp to only remove two config variables
# TODO figure out how to add it so it starts at TrueNAS boot
#sed -i "s/,\ \"bridge\"[^}]*//" /etc/docker/daemon.json;
#sed -i "s/,\ \"iptables\"[^}]*//" /etc/docker/daemon.json; 
# old
#service docker restart;
# TODO FIXME workaround for above
cp /mnt/MargokPool/home/sup/code/bash_configs/nas/daemon.json.CHANGED /etc/docker/daemon.json

# new
service docker restart; service k3s restart; service docker restart; 
service docker status; service k3s status

# when k3s doesn't start: https://github.com/kubernetes/kubernetes/issues/66241#issuecomment-460832038

