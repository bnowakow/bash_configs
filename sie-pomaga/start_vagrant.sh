#!/bin/bash

vagrant up;
vagrant provision;
# TODO
echo TODO figure out a way to do vagrant ssh docker exec in order to check if kibana is up or just run provisioning script in loop until code 0 is returned
echo waiting kibana to start
sleep 10m;
vagrant ssh -c "/mnt/MargokPool/home/sup/code/bash_configs/nas/zabbix/sie-pomaga/config/beats/filebeat/1-after_first_launch.sh"

