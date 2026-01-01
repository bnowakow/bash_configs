#!/bin/bash

home_assistant_running_in_vagrant=false

cd /mnt/MargokPool/home/sup/code/bash_configs/home-assistant/zabbix;
source lib/ha-running-in-vagrant-on-in-proxmox.sh

# when we're running ha in supervised or in contenerized we're logging into vm/host and exacuting command against docker container
#os_version_local=$(ssh root@$ssh_host $ssh_port 'docker exec hassio_cli ha info' 2>/dev/null | grep 'hassos:' | sed 's/\"//g' | sed 's/.*\ //')
# when we're running haos on proxmox then we're not logging into VM but into ssh add-on
os_version_local=$(ssh root@$ssh_host $ssh_port 'ha info' 2>/dev/null | grep 'hassos:' | sed 's/\"//g' | sed 's/.*\ //')
os_version_current=$(curl https://api.github.com/repositories/115992009/releases/latest 2>/dev/null | jq '.tag_name' | sed 's/\"//g')

if [ "$os_version_local" = "$os_version_current" ]; then
    echo true;
else
    echo false,$os_version_local,$os_version_current
fi

