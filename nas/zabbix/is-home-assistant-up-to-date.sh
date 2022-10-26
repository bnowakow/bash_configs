#!/bin/bash

cd /mnt/MargokPool/home/sup/code/bash_configs/nas/home-assistant
ha_version_local=$(ssh root@192.168.1.67 'docker exec hassio_cli ha info' 2>/dev/null | grep 'homeassistant:' | sed 's/.*\ //')
ha_version_current=$(curl https://api.github.com/repositories/12888993/releases/latest 2>/dev/null | jq '.tag_name' | sed 's/\"//g')

if [ "$ha_version_local" = "$ha_version_current" ]; then
    echo true
else
    echo false,$ha_version_local,$ha_version_current
fi

