#!/bin/bash -x

# todo check if u can set mount_path in main script and use it in sourced one
# todo check return codes of mounting, maybe rsync
source lib/mount_apfs.sh
sudo ls -la $mount_path_tm

sudo rsync -a $mount_path_tm $backup_path_tm

sudo umount $mount_path

cd $backup_path
reversed_directories_tm=$(ls -r -d */)
sudo jdupes --delete --noprompt -r -Z -O $reversed_directories_tm
sudo find "$backup_path" -depth -type d -empty -delete;

cd /mnt/MargokPool/home/sup/code/docker-jdupes-gui
docker-compose up
docker-compose down

sudo find "$backup_path" -depth -type d -empty -delete;

