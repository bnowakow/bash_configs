#!/bin/bash -x

source lib/mount_apfs.sh

cd $backup_path
# first pass on latest laptop TimeMachine
sudo jdupes --delete --noprompt -r -Z -O Taerar7/

# second pass on TimeMachine from all laptops
reversed_directories_tm=$(ls -r -d */)
sudo jdupes --delete --noprompt -r -Z -O $reversed_directories_tm
sudo find "$backup_path" -depth -type d -empty -delete;

# third pass on TimeMachine from all laptops and directories on NAS
cd /mnt/MargokPool/home/sup/code/docker-jdupes-gui
docker-compose up
docker-compose down
sudo find "$backup_path" -depth -type d -empty -delete;

