#!/bin/bash

host=ovh.bnowakowski.pl
remote_dir=/backup
remote_file_name="sup*"
local_dir=/Users/sup/code/ovh/backup
number_of_backpus_to_keep=3

rsync --partial --progress --rsh=ssh -r --remove-source-files $host:\"$remote_dir/$remote_file_name\" "$local_dir"
let number_of_backpus_to_keep=$number_of_backpus_to_keep+1;
ls -d -1t $local_dir/* | tail -n +$number_of_backpus_to_keep | xargs rm
