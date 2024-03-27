#!/bin/bash

# https://www.truenas.com/community/threads/nfs-no_root_squash.84258/post-582617

for mount_point in "/mnt/PlexPool/plex" "/mnt/MargokPool/archive" "/mnt/MargokPool/home"; do
    if ! grep "$mount_point" -A1 /etc/exports | grep "no_root_squash" > /dev/null; then
        echo false,$mount_point;
        exit
    fi
done

echo true

