#!/bin/bash

home_assistant_running_in_vagrant=true

cd /mnt/MargokPool/home/sup/code/bash_configs/home-assistant/zabbix;
source lib/ha-running-in-vagrant-on-in-proxmox.sh

echo ssh_port=$ssh_port
echo ssh_host=$ssh_host

remote_user=root
remote_dir="/backup"
remote_file_name="*.tar"

local_dir_prefix="/mnt/MargokPool/archive/Backups"
local_dir_suffix="home-assistant"
local_dir="$local_dir_prefix/$local_dir_suffix"

number_of_backpus_to_keep=30

mkdir -p "$local_dir"
remote_path="$remote_dir/$remote_file_name";
rsync --partial --progress --rsh=ssh -r --remove-source-files -e "ssh $ssh_port -i $HOME/.ssh/id_rsa" $remote_user@$ssh_host:$remote_path $local_dir;

number_of_backup_files=$(ls -d -1t $local_dir/* | wc -l);
if [ $number_of_backup_files -gt $number_of_backpus_to_keep ]; then
    ls -d -1t $local_dir/* | tail -n +$number_of_backpus_to_keep | xargs rm;
fi

# rename backup files to include date
cd $local_dir
for file in $(ls -1 *tar | grep -v 'homeassistant_'); do
    new_name=$(find . -maxdepth 1 -name $file -type f -printf "homeassistant_%TY-%Tm-%Td_%TH-%TM_%f\n";)
    mv $file $new_name
done

# rotate backup for crashplan (it holds only 1 backup out of 10 to not send too much data)
local_one_file_backup_dir="$local_dir_prefix/one_file_backup/$local_dir_suffix"
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
    cp $(ls -d -1t $local_dir/*tar | head -n1) $local_one_file_backup_dir
fi
