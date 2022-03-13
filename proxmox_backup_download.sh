#!/bin/bash


remote_user="root"
remote_host="192.168.1.56"
remote_dir="/etc/pve/qemu-server"
remote_file_name="*.conf*"

local_dir="/mnt/MargokPool/archive/Documents/proxmox"

number_of_backpus_to_keep=10

mkdir -p "$local_dir"
remote_path="$remote_dir/$remote_file_name";
rsync --partial --progress --rsh=ssh -r $remote_user@$remote_host:$remote_path $local_dir;

cd $local_dir
tar -czvf proxmox_`date +"%Y-%m-%d_%H-%M"`.tar.gz $remote_file_name;
rm $remote_file_name;

let number_of_backpus_to_keep=$number_of_backpus_to_keep+1;

number_of_backup_files=$(ls -d -1t $local_dir/$user* | wc -l);
if [ $number_of_backup_files -gt $number_of_backpus_to_keep ]; then
    ls -d -1t * | tail -n +$number_of_backpus_to_keep | xargs rm;
fi
