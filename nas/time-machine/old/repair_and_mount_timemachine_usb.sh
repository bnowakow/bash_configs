#!/bin/bash

disk_device=$(lsscsi | grep Elements | awk '{print $7}')
partition_number=2

partition_device=$disk_device$partition_number
echo $partition_device

while true; do	
	if ! mount | grep hfsplus | grep rw; then
	        sudo umount /media/tm
        	sudo fsck.hfsplus $partition_device
        	sudo mount -t hfsplus -o force,rw $partition_device /media/tm
	else
		echo "hfsplus mounted as rw";
                break;
	fi
done

ls /media/tm
