#!/bin/bash

os_version_local=$(ssh root@192.168.0.30 'docker exec hassio_cli ha info' 2>/dev/null | grep 'hassos:' | sed 's/\"//g' | sed 's/.*\ //')
os_version_current=$(curl https://api.github.com/repositories/115992009/releases/latest 2>/dev/null | jq '.tag_name' | sed 's/\"//g')

if [ "$os_version_local" = "$os_version_current" ]; then
    echo true;
else
    echo false,$os_version_local,$os_version_current
fi

