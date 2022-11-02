#!/bin/bash

# when backup errors during, doesn't finish and can't start new one: https://forum.vestacp.com/viewtopic.php?f=10&t=16357

remote_host=ovh.bnowakowski.pl
remote_dir="/backup"

local_dir_prefix="/mnt/MargokPool/archive/Backups"

number_of_backpus_to_keep=10
let number_of_backpus_to_keep=$number_of_backpus_to_keep+1;

user_names=( sup admin );
for user_name in "${user_names[@]}"; do
    echo $user_name;
    local_dir="$local_dir_prefix/ovh-$user_name"
    remote_path="$remote_dir/$user_name*.tar";
    mkdir -p "$local_dir"
    
    # download new backup
    rsync --partial --progress --rsh=ssh -r --remove-source-files -e "ssh -i $HOME/.ssh/id_rsa" $remote_host:$remote_path $local_dir;

    # rotate old backups
    number_of_backup_files=$(ls -d -1t $local_dir/$user_name* | wc -l);
    if [ $number_of_backup_files -gt $number_of_backpus_to_keep ]; then
        ls -d -1t $local_dir/$user_name* | tail -n +$number_of_backpus_to_keep | xargs rm;
    fi
done

