#!/bin/bash

disk_grep="2105";
column_number=6;

disk_grep="Elements";
column_number=7;

disk_device=$(lsscsi | grep $disk_grep | awk '{print $'$column_number'}')
partition_number=2

partition_device=$disk_device$partition_number
echo $partition_device

# https://linuxnewbieguide.org/how-to-mount-macos-apfs-disk-volumes-in-linux/
#sudo apfs-fuse -o allow_other $partition_device /media/tm #ro

# https://www.reddit.com/r/datarecovery/comments/kkamgy/apfs_rw_support_for_linux/
sudo fsapfsmount -f 1 $partition_device /media/Taerar7 #rw

sudo ls /media/Taerar7
