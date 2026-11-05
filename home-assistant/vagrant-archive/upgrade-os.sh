#!/bin/bash

cd /mnt/MargokPool/home/sup/code/homelab/nas/home-assistant;
# TODO take latest version from zabbix script
ssh root@192.168.1.67  "ha os update --version 9.4"

