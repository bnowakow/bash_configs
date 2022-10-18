#!/bin/bash


remote_user="root"
remote_host="192.168.1.56"

local_dir="/mnt/MargokPool/archive/Backups/proxmox"
current_backup_local_dir="$local_dir/current"

number_of_backpus_to_keep=30

mkdir -p "$current_backup_local_dir"


# KVM configs
remote_dir="/etc/pve/qemu-server"
remote_file_name="*.conf*"
remote_path="$remote_dir/$remote_file_name";
rsync --partial --progress --rsh=ssh -r $remote_user@$remote_host:$remote_path $current_backup_local_dir;

# modprobe.d
remote_dir="/etc/modprobe.d/"
remote_path="$remote_dir/$remote_file_name";
rsync --partial --progress --rsh=ssh -r $remote_user@$remote_host:$remote_path $current_backup_local_dir;


remote_dir="/etc/default/grub"
rsync --partial --progress --rsh=ssh -r $remote_user@$remote_host:$remote_dir $current_backup_local_dir;

remote_dir="/etc/modules"
rsync --partial --progress --rsh=ssh -r $remote_user@$remote_host:$remote_dir $current_backup_local_dir;

cd $current_backup_local_dir
tar -czvf proxmox.`date +"%Y-%m-%d_%H-%M"`.tar.gz *;
mv *.tar.gz ../
cd ..
rm -rf $current_backup_local_dir

let number_of_backpus_to_keep=$number_of_backpus_to_keep+1;

number_of_backup_files=$(ls -d -1t $local_dir/* | wc -l);
if [ $number_of_backup_files -gt $number_of_backpus_to_keep ]; then
    ls -d -1t * | tail -n +$number_of_backpus_to_keep | xargs rm;
fi
