#!/bin/bash -x

# TODO export constants to separate file in lib/mount_apfs.sh and source it here
backup_path=/mnt/MargokPool/archive/TimeMachine
# /TODO

cd $backup_path
reversed_directories_tm=$(ls -r -d */)
sudo jdupes --delete --noprompt -r -Z -O $reversed_directories_tm
sudo find "$backup_path" -depth -type d -empty -delete;

# TODO DEBUG
exit

cd /mnt/MargokPool/home/sup/code/docker-jdupes-gui
docker-compose up
docker-compose down

sudo find "$backup_path" -depth -type d -empty -delete;

