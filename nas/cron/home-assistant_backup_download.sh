#!/bin/bash

home_assistant_running_in_vagrant=true

cd /mnt/MargokPool/home/sup/code/bash_configs/home-assistant/zabbix;
source lib/ha-running-in-vagrant-on-in-proxmox.sh

echo ssh_port=$ssh_port
echo ssh_host=$ssh_host

remote_user=root
remote_dir="/backup"
remote_file_name="*.tar"

local_dir="/mnt/MargokPool/archive/Backups/home-assistant"

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

