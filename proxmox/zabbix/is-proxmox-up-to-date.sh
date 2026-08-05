#!/bin/bash

# https://subscription.packtpub.com/book/cloud-&-networking/9781783980901/11/ch11lvl1sec94/proxmox-commands
# https://www.youtube.com/watch?v=NHAUugksnvA

local_version=$(pveversion -v | grep proxmox-ve | sed 's/proxmox-ve: //' | sed 's/ .running.*//' | sed 's/\.[0-9]*$//')
# The download name may include a build number and architecture (for example,
# 9.2-1-arm64). Compare only the base Proxmox version with the local version.
current_version=$(curl https://www.proxmox.com/en/downloads/proxmox-virtual-environment/iso 2>/dev/null| grep '\.iso' | head -1 | sed 's/.*proxmox-ve_//' | sed 's/.iso.*//' | sed 's/-.*//')

if [ "$local_version" = "$current_version" ]; then
    echo true
else
    echo false,$local_version,$current_version
fi

