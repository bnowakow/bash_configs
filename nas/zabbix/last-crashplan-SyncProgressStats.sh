#!/bin/bash

log_file_name_prefix="service.log";

for log_file in `sudo /usr/bin/su sup -c "cd /mnt/MargokPool/home/sup/code/crashplan-docker; vagrant ssh -c 'sudo ls -1t /usr/local/crashplan/log | grep $log_file_name_prefix '" 2>/dev/null`; do

    # remove \r that for some reason is at the end o.O
    log_file=$(echo $log_file | tr -d '\r')

    #echo $log_file

    log_line=$(sudo /usr/bin/su sup -c "cd /mnt/MargokPool/home/sup/code/crashplan-docker; vagrant ssh -c 'sudo grep SyncProgressStats /usr/local/crashplan/log/$log_file | grep -v Binary\ file | tail -1'" 2>/dev/null);

    if [ ! "$log_line" = "" ]; then
        percent=$(echo $log_line | sed "s/.*total=[0-9]*..//" | sed "s/%.*/%/");
        date_time=$(echo $log_line | sed "s/^.//" | sed "s/.INFO.*//")
        echo $percent, $date_time
        exit
    fi
done

echo false

