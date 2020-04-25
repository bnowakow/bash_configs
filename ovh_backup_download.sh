#!/bin/bash

host=ovh.bnowakowski.pl
remote_dir=/backup
local_dir="/Users/sup/code/ovh/backup"
remote_file_name="sup*"
remote_file_name="*.tar"
remote_file_name="*.zip"
number_of_backpus_to_keep=3

mkdir -p "$local_dir"
remote_path="$remote_dir/$remote_file_name";
rsync --partial --progress --rsh=ssh -r --remove-source-files $host:$remote_path $local_dir;
let number_of_backpus_to_keep=$number_of_backpus_to_keep+1;
ls -d -1t $local_dir/* | tail -n +$number_of_backpus_to_keep | xargs rm;
