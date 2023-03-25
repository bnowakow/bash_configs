#!/bin/bash -x

# todo check return codes of mounting, maybe rsync
source lib/mount_apfs.sh
sudo ls -la $mount_path_tm

sudo rsync -a $mount_path_tm $backup_path_tm

sudo umount $mount_path

