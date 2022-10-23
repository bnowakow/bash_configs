#!/bin/bash

remote_host=192.168.1.67
remote_user=root
remote_dir="/backup"
remote_file_name="*.tar"

local_dir="/mnt/MargokPool/archive/Backups/home-assistant"

number_of_backpus_to_keep=30

mkdir -p "$local_dir"
remote_path="$remote_dir/$remote_file_name";
rsync --partial --progress --rsh=ssh -r --remove-source-files -e "ssh -i $HOME/.ssh/id_rsa" $remote_user@$remote_host:$remote_path $local_dir;

number_of_backup_files=$(ls -d -1t $local_dir/* | wc -l);
if [ $number_of_backup_files -gt $number_of_backpus_to_keep ]; then
    ls -d -1t $local_dir/* | tail -n +$number_of_backpus_to_keep | xargs rm;
fi

