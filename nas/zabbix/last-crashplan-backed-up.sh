#!/bin/bash

log_file_name_prefix="backup_files.log";

for log_file in `sudo /usr/bin/su sup -c "cd /mnt/MargokPool/home/sup/code/crashplan-docker; vagrant ssh -c 'sudo crashplan ls -1t /usr/local/crashplan/log | grep $log_file_name_prefix '" 2>/dev/null`; do

    # remove \r that for some reason is at the end o.O
    log_file=$(echo $log_file | tr -d '\r')

    #echo $log_file

    log_line=$(sudo /usr/bin/su sup -c "cd /mnt/MargokPool/home/sup/code/crashplan-docker; vagrant ssh -c 'sudo grep backed\ up /usr/local/crashplan/log/$log_file | tail -1'" 2>/dev/null)

    if [ ! "$log_line" = "" ]; then
        stats=$(echo $log_line | sed "s/^.*Online in//" | sed "s/backed up.*/backed up/");
        date_time=$(echo $log_line | sed "s/^..//" | sed "s/\[.*//")
        echo $stats, $date_time
        exit
    fi

done

echo false

