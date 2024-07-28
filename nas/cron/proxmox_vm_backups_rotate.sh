#!/bin/bash

local_dir_prefix="/mnt/MargokPool/archive/Backups"
local_dir_suffix="proxmox/dump"
local_dir="$local_dir_prefix/$local_dir_suffix"

local_one_file_backup_dir="$local_dir_prefix/one_file_backup/$local_dir_suffix"
mkdir -p $local_one_file_backup_dir;

rotate_every_days=30
# https://stackoverflow.com/a/77334969
# date 30 days ago
cut_of_date=$(date -u +"%F %T" -d "$rotate_every_days days ago")
#echo DEBUG cut_of_date=$cut_of_date

for file_prefix in $(ls $local_dir_prefix/$local_dir_suffix -1 | sed 's/-[0-9][0-9][0-9][0-9].*//' | sort | uniq); do 
    one_file_backup_needs_to_be_copied=0;
    echo $file_prefix;
    if [ $(ls -d -1t $local_one_file_backup_dir/$file_prefix* 2> /dev/null | wc -l) -gt 0 ]; then
        echo $file_prefix has a one_file_backup
        current_one_file_backup=$(ls -d -1t $local_one_file_backup_dir/$file_prefix* | head -n 1)
        #echo DEBUG $(ls -la $current_one_file_backup)
        #echo DEBUG $(stat -c '%y' $current_one_file_backup)
        current_one_file_backup_creation_date=$(stat -c '%y' $current_one_file_backup)
        #echo DEBUG current_one_file_backup_creation_date=$current_one_file_backup_creation_date
        if [[ $current_one_file_backup_creation_date < $cut_of_date ]]; then
            echo "older than $rotate_every_days days"
            rm $local_one_file_backup_dir/$file_prefix*
            one_file_backup_needs_to_be_copied=1
        else
            echo "newer than $rotate_every_days days"
        fi
    else
        echo $file_prefix doesn\'t have a one_file_backup
        one_file_backup_needs_to_be_copied=1
    fi

    if [ $one_file_backup_needs_to_be_copied -eq 1 ]; then
        # each backup has .log, .vma.zst.notes and .vma.zst files
        rsync -a $(ls -d -1t $local_dir/$file_prefix* | head -n3) $local_one_file_backup_dir
    fi

done


