#!/bin/bash

remote_user="root"
remote_host="192.168.0.10"

local_dir="/mnt/MargokPool/archive/Backups/proxmox"
current_backup_local_dir="$local_dir/current"

number_of_backpus_to_keep=30

mkdir -p "$current_backup_local_dir"

# TODO remove all of of repetitions that should be functions

# KVM configs
remote_dir="/etc/pve/qemu-server"
remote_file_name="*.conf*"
remote_path="$remote_dir/$remote_file_name";
rsync --partial --progress --rsh=ssh -r $remote_user@$remote_host:$remote_path $current_backup_local_dir/qemu-server;
number_of_copied_files=$(find $current_backup_local_dir/qemu-server -type f -name "$remote_file_name" | wc -l)
if [ $number_of_copied_files = 0 ]; then
    echo copy of $remote_dir failed
    rm -rf $current_backup_local_dir
    exit
else
    echo copied $number_of_copied_files files from remote_dir
fi

# modprobe.d
remote_dir="/etc/modprobe.d/"
remote_path="$remote_dir/$remote_file_name";
rsync --partial --progress --rsh=ssh -r $remote_user@$remote_host:$remote_path $current_backup_local_dir/modprobe.d;
number_of_copied_files=$(find $current_backup_local_dir/modprobe.d -type f | wc -l)
if [ $number_of_copied_files = 0 ]; then
    echo copy of $remote_dir failed
    rm -rf $current_backup_local_dir
    exit
else
    echo copied $number_of_copied_files files from $remote_dir
fi

remote_dir="/var/lib/vz/snippets"
remote_file_name="*.sh"
remote_path="$remote_dir/$remote_file_name";
mkdir -p $current_backup_local_dir/snippets
rsync --partial --progress --rsh=ssh -r $remote_user@$remote_host:$remote_path $current_backup_local_dir/snippets;
number_of_copied_files=$(find $current_backup_local_dir/snippets -type f -name "$remote_file_name" | wc -l)
if [ $number_of_copied_files = 0 ]; then
    echo copy of $remote_dir failed
    rm -rf $current_backup_local_dir
    exit
else
    echo copied $number_of_copied_files files from $remote_dir
fi

remote_dir="/etc/default/grub"
rsync --partial --progress --rsh=ssh -r $remote_user@$remote_host:$remote_dir $current_backup_local_dir;
number_of_copied_files=$(find $current_backup_local_dir/grub -type f | wc -l)
if [ $number_of_copied_files = 0 ]; then
    echo copy of $remote_dir failed
    rm -rf $current_backup_local_dir
    exit
else
    echo copied $number_of_copied_files files from $remote_dir
fi


remote_dir="/etc/modules"
rsync --partial --progress --rsh=ssh -r $remote_user@$remote_host:$remote_dir $current_backup_local_dir;
number_of_copied_files=$(find $current_backup_local_dir/modules -type f | wc -l)
if [ $number_of_copied_files = 0 ]; then
    echo copy of $remote_dir failed
    rm -rf $current_backup_local_dir
    exit
else
    echo copied $number_of_copied_files files from $remote_dir
fi

remote_dir="/etc/apt/sources.list"
rsync --partial --progress --rsh=ssh -r $remote_user@$remote_host:$remote_dir $current_backup_local_dir;
number_of_copied_files=$(find $current_backup_local_dir/sources.list -type f | wc -l)
if [ $number_of_copied_files = 0 ]; then
    echo copy of $remote_dir failed
    rm -rf $current_backup_local_dir
    exit
else
    echo copied $number_of_copied_files files from $remote_dir
fi

remote_dir="/etc/sudoers"
rsync --partial --progress --rsh=ssh -r $remote_user@$remote_host:$remote_dir $current_backup_local_dir
number_of_copied_files=$(find $current_backup_local_dir/sudoers -type f | wc -l)
if [ $number_of_copied_files = 0 ]; then
    echo copy of $remote_dir failed
    rm -rf $current_backup_local_dir
    exit
else
    echo copied $number_of_copied_files files from $remote_dir
fi


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
