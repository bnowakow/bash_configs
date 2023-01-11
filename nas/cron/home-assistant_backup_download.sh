#!/bin/bash

remote_host=192.168.0.30
remote_user=root
remote_dir="/backup"
remote_file_name="*.tar"

local_dir="/mnt/MargokPool/archive/Backups/home-assistant"

number_of_backpus_to_keep=30

mkdir -p "$local_dir"
remote_path="$remote_dir/$remote_file_name";
rsync --partial --progress --rsh=ssh -r --remove-source-files -e "ssh -i $HOME/.ssh/id_rsa" $remote_user@$remote_host:$remote_path $local_dir;

number_of_backup_files=$(ls -d -1t $local_dir/* | wc -l);
if [ $number_of_backup_files -gt $number_of_backpus_to_keep ]; then
    ls -d -1t $local_dir/* | tail -n +$number_of_backpus_to_keep | xargs rm;
fi

# rename backup files to include date
cd $local_dir
for file in $(ls -1 *tar | grep -v 'homeassistant_'); do
    new_name=$(find . -maxdepth 1 -name $file -type f -printf "homeassistant_%TY-%Tm-%Td_%TT_%f\n";)
    mv $file $new_name
done

