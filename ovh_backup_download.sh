#!/bin/bash

host=ovh.bnowakowski.pl
remote_dir=/backup
remote_file_name="sup*"
local_dir="/media/Airport-Store-Small/Data/ovh/"
number_of_backpus_to_keep=10

mkdir -p "$local_dir"
remote_path="$remote_dir/$remote_file_name";
rsync --partial --progress --rsh=ssh -r --remove-source-files $host:$remote_path $local_dir;
let number_of_backpus_to_keep=$number_of_backpus_to_keep+1;
ls -d -1t $local_dir/* | tail -n +$number_of_backpus_to_keep | xargs rm;


local_dir="/media/Airport-Store-Small/Data/pine64/ubuntu-16.04"; 
mkdir -p "$local_dir"; 
rsync --partial --progress -r --exclude /media/ --exclude /dev --exclude /proc --exclude /sys / $local_dir
