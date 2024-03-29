#!/bin/bash

number_of_backpus_to_keep=10
backup_path=/home/sup/code/bash_configs/ovh/cron/etc-backup

mkdir -p $backup_path

number_of_backup_files=$(ls -d -1t $backup_path/*.tar.gz | wc -l);
if [ $number_of_backup_files -gt $number_of_backpus_to_keep ]; then
    ls -d -1t $backup_path/*.tar.gz | tail -n +$number_of_backpus_to_keep | xargs rm;
fi

date_stamp=$(date +"%Y-%m-%d_%H-%M")
sudo cp -r /etc $backup_path/etc-$date_stamp
sudo tar -cvzf $backup_path/etc-"$date_stamp".tar.gz $backup_path/etc-$date_stamp
sudo rm -rf $backup_path/etc-$date_stamp


