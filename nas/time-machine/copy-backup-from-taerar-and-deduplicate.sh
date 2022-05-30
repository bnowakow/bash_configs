#!/bin/bash

# todo check if u can set mount_path in main script and use it in sourced one

source lib/mount_apfs.sh
sudo ls -la $mount_path

backup_path=/mnt/MargokPool/archive/TimeMachine

sudo rsync -a --no-links $mount_path $backup_path 2>&1 | grep -v "skipping non-regular file"

