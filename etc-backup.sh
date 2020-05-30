#!/bin/bash

number_of_backpus_to_keep=10
backup_path=etc-backup

mkdir -p $backup_path
ls -1t $backup_path/*.tar.gz | tail -n +$number_of_backpus_to_keep | xargs rm;

date_stamp=$(date +"%Y-%m-%d_%H-%M")
sudo cp -r /etc $backup_path/etc-$date_stamp
sudo tar -cvzf $backup_path/etc-"$date_stamp".tar.gz $backup_path/etc-$date_stamp
sudo rm -rf $backup_path/etc-$date_stamp


