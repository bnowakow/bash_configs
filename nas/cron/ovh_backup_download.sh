#!/bin/bash

# when backup errors during, doesn't finish and can't start new one: https://forum.vestacp.com/viewtopic.php?f=10&t=16357

remote_host=ovh.bnowakowski.pl
remote_dir="/backup"

local_dir_prefix="/mnt/MargokPool/archive/Backups"

number_of_backpus_to_keep=30
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

    # rotate backup for crashplan (it holds only 1 backup out of 10 to not send too much data)
    local_one_file_backup_dir="$local_dir_prefix/one_file_backup/ovh-$user_name"
    mkdir -p $local_one_file_backup_dir;
    one_file_backup_needs_to_be_copied=0;
    if [ $(ls -d -1t $local_one_file_backup_dir/* | wc -l) -gt 0 ]; then
        # backup for crashplan already exists
        current_one_file_backup=$(ls -d -1t $local_one_file_backup_dir/* | head -n 1 | sed 's/.*\///')
        if [ $(find $local_dir -name $current_one_file_backup | wc -l) -eq 0  ]; then
            rm $local_one_file_backup_dir/*;
            one_file_backup_needs_to_be_copied=1
        fi
    else
        # backup for crashplan doesn't exist
        one_file_backup_needs_to_be_copied=1
    fi

    if [ $one_file_backup_needs_to_be_copied -eq 1 ]; then
        cp $(ls -d -1t $local_dir/$user_name* | head -n1) $local_one_file_backup_dir
    fi
done

