#!/bin/bash


home_assistant_running_in_vagrant=true

cd /mnt/MargokPool/home/sup/code/bash_configs/home-assistant/zabbix;
source lib/ha-running-in-vagrant-on-in-proxmox.sh

os_version_local=$(ssh root@$ssh_host $ssh_port 'docker exec hassio_cli ha info' 2>/dev/null | grep 'hassos:' | sed 's/\"//g' | sed 's/.*\ //')
os_version_current=$(curl https://api.github.com/repositories/115992009/releases/latest 2>/dev/null | jq '.tag_name' | sed 's/\"//g')

if [ "$os_version_local" = "$os_version_current" ]; then
    echo true;
else
    echo false,$os_version_local,$os_version_current
fi

