#!/bin/bash

remote_host=ovh.bnowakowski.pl
remote_dir="/backup"
remote_file_name="*.tar"

local_dir="/mnt/MargokPool/archive/Documents/ovh"

number_of_backpus_to_keep=10

mkdir -p "$local_dir"
remote_path="$remote_dir/$remote_file_name";
rsync --partial --progress --rsh=ssh -r --remove-source-files $remote_host:$remote_path $local_dir;

let number_of_backpus_to_keep=$number_of_backpus_to_keep+1;
for user in $( ls -1 $local_dir | sed 's/\..*//' | sort | uniq ); do
    echo $user;
    number_of_backup_files=$(ls -d -1t $local_dir/$user* | wc -l);
    if [ $number_of_backup_files -gt $number_of_backpus_to_keep ]; then
        ls -d -1t $local_dir/$user* | tail -n +$number_of_backpus_to_keep | xargs rm;
    fi
done
