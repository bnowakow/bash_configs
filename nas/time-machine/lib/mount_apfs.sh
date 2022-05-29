#!/bin/bash

disk_grep="2105";
column_number=6;

disk_grep="Elements";
column_number=7;

mount_path=/media/Taerar7
sudo mkdir -p $mount_path

disk_device=$(lsscsi | grep $disk_grep | awk '{print $'$column_number'}')
partition_number=2

partition_device=$disk_device$partition_number
echo $partition_device

# https://linuxnewbieguide.org/how-to-mount-macos-apfs-disk-volumes-in-linux/
#sudo apfs-fuse -o allow_other $partition_device $mount_path #ro

# https://www.reddit.com/r/datarecovery/comments/kkamgy/apfs_rw_support_for_linux/
sudo fsapfsmount -f 1 $partition_device $mount_path #rw

sudo find $mount_path -maxdepth 1 -name "*.backup" | sudo xargs -I{} ls -l {}/Data
