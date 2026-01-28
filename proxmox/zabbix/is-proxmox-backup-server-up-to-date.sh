#!/bin/bash

# https://forum.proxmox.com/threads/pveversion-pmgversion-any-equivalent-for-pbsversion.141595/

local_version=$(sudo proxmox-backup-manager version --verbose | grep proxmox-backup-server | sed 's/.*running\ version\:\ //' | sed 's/[^0-9]*$//' | sed 's/\.[0-9]*$//')
current_version=$(curl https://www.proxmox.com/en/downloads/proxmox-backup-server/iso 2>/dev/null| grep '\.iso' | head -1 | sed 's/.*proxmox-backup-server_//' | sed 's/.iso.*//' | sed 's/-[0-9]*//')

if [ "$local_version" = "$current_version" ]; then
    echo true
else
    echo false,$local_version,$current_version
fi


