#!/bin/bash

last_version_to_save=$(sudo zfs list -H -o name -t snapshot $snap -s creation | grep boot-pool | sed 's/boot-pool.ROOT.//' | sed 's/\/.*//' | uniq | tail -1)
second_last_version_to_save=$(sudo zfs list -H -o name -t snapshot $snap -s creation | grep boot-pool | sed 's/boot-pool.ROOT.//' | sed 's/\/.*//' | uniq | tail -2 | head -1)
echo "Will save snapshots of versions $last_version_to_save and $second_last_version_to_save. Will delete others"

for snapshot in $(sudo zfs list -H -o name -t snapshot $snap -s creation | grep boot-pool | grep -v $second_last_version_to_save | grep -v $last_version_to_save); do
    sudo zfs destroy -r -R $snapshot;
done

