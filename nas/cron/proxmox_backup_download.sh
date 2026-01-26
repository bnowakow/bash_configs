#!/bin/bash

remote_user="root"

remote_hosts=( proxmox2.localdomain.bnowakowski.pl proxmox3.localdomain.bnowakowski.pl proxmox4.localdomain.bnowakowski.pl );
for remote_host in "${remote_hosts[@]}"; do
    echo $remote_host
local_dir="/mnt/MargokPool/archive/Backups/proxmox/config"
current_backup_local_dir="$local_dir/current"

# TODO below is workaround since we're backing 3 proxmox servers it's 3*30m but it doesn't keep last 30 from each of them but just last 90 which is an edge case
number_of_backpus_to_keep=90

mkdir -p "$current_backup_local_dir"

# TODO remove all of of repetitions that should be functions

# KVM configs
remote_dir="/etc/pve/qemu-server"
remote_file_name="*.conf*"
remote_path="$remote_dir/$remote_file_name";
rsync --partial --progress --rsh=ssh -r $remote_user@$remote_host:$remote_path $current_backup_local_dir/qemu-server/;
number_of_copied_files=$(find $current_backup_local_dir/qemu-server -type f -name "$remote_file_name" | wc -l)
if [ $number_of_copied_files = 0 ]; then
    echo copy of $remote_dir on $remote_host failed
    rm -rf $current_backup_local_dir
    exit
else
    echo copied $number_of_copied_files files from remote_dir
fi

# modprobe.d
remote_dir="/etc/modprobe.d/"
remote_path="$remote_dir/$remote_file_name";
rsync --partial --progress --rsh=ssh -r $remote_user@$remote_host:$remote_path $current_backup_local_dir/modprobe.d/;
number_of_copied_files=$(find $current_backup_local_dir/modprobe.d -type f | wc -l)
if [ $number_of_copied_files = 0 ]; then
    echo copy of $remote_dir on $remote_host failed
    rm -rf $current_backup_local_dir
    exit
else
    echo copied $number_of_copied_files files from $remote_dir
fi

#remote_dir="/var/lib/vz/snippets"
#remote_file_name="*.sh"
#remote_path="$remote_dir/$remote_file_name";
#mkdir -p $current_backup_local_dir/snippets
#rsync --partial --progress --rsh=ssh -r $remote_user@$remote_host:$remote_path $current_backup_local_dir/snippets/;
#number_of_copied_files=$(find $current_backup_local_dir/snippets -type f -name "$remote_file_name" | wc -l)
#if [ $number_of_copied_files = 0 ]; then
#    echo copy of $remote_dir failed
#    rm -rf $current_backup_local_dir
#    exit
#else
#    echo copied $number_of_copied_files files from $remote_dir
#fi

remote_dir="/etc/default/grub"
rsync --partial --progress --rsh=ssh -r $remote_user@$remote_host:$remote_dir $current_backup_local_dir/;
number_of_copied_files=$(find $current_backup_local_dir/grub -type f | wc -l)
if [ $number_of_copied_files = 0 ]; then
    echo copy of $remote_dir on $remote_host failed
    rm -rf $current_backup_local_dir
    exit
else
    echo copied $number_of_copied_files files from $remote_dir
fi


remote_dir="/etc/modules"
rsync --partial --progress --rsh=ssh -r $remote_user@$remote_host:$remote_dir $current_backup_local_dir/;
number_of_copied_files=$(find $current_backup_local_dir/modules -type f | wc -l)
if [ $number_of_copied_files = 0 ]; then
    echo copy of $remote_dir on $remote_host failed
    rm -rf $current_backup_local_dir
    exit
else
    echo copied $number_of_copied_files files from $remote_dir
fi

remote_dir="/etc/apt/sources.list"
rsync --partial --progress --rsh=ssh -r $remote_user@$remote_host:$remote_dir $current_backup_local_dir/;
remote_dir="/etc/apt/sources.list.bak"
rsync --partial --progress --rsh=ssh -r $remote_user@$remote_host:$remote_dir $current_backup_local_dir/;
number_of_copied_files=$(find "$current_backup_local_dir/sources.list" -type f | wc -l)
number_of_copied_files_bak=$(find "$current_backup_local_dir/sources.list.bak" -type f | wc -l)
if [ "$number_of_copied_files" = 0 ] && [ "$number_of_copied_files_bak" = 0 ]; then
    echo copy of $remote_dir on $remote_host failed
    rm -rf $current_backup_local_dir
    exit
else
    echo copied $number_of_copied_files files from $remote_dir
fi

remote_dir="/etc/apt/sources.list.d"
rsync --partial --progress --rsh=ssh -r $remote_user@$remote_host:$remote_dir $current_backup_local_dir/;
number_of_copied_files=$(find "$current_backup_local_dir/sources.list.d" -type f | wc -l)
if [ $number_of_copied_files = 0 ]; then
    echo copy of $remote_dir on $remote_host failed
    rm -rf $current_backup_local_dir
    exit
else
    echo copied $number_of_copied_files files from $remote_dir
fi

#remote_dir="/etc/sudoers"
#rsync --partial --progress --rsh=ssh -r $remote_user@$remote_host:$remote_dir $current_backup_local_dir/
#number_of_copied_files=$(find $current_backup_local_dir/sudoers -type f | wc -l)
#if [ $number_of_copied_files = 0 ]; then
#    echo copy of $remote_dir failed
#    rm -rf $current_backup_local_dir
#    exit
#else
#    echo copied $number_of_copied_files files from $remote_dir
#fi


cd $current_backup_local_dir
tar -czvf proxmox-$remote_host.`date +"%Y-%m-%d_%H-%M"`.tar.gz *;
mv *.tar.gz ../
cd ..
rm -rf $current_backup_local_dir

# TODO +3 because we've 3 proxmox servers
let number_of_backpus_to_keep=$number_of_backpus_to_keep+3;

number_of_backup_files=$(ls -d -1t $local_dir/* | wc -l);
if [ $number_of_backup_files -gt $number_of_backpus_to_keep ]; then
    ls -d -1t * | tail -n +$number_of_backpus_to_keep | xargs rm;
fi

done
