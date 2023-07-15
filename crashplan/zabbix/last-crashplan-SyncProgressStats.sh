#!/bin/bash

log_file_name_prefix="service.log";

for log_file in `ls -1t /usr/local/crashplan/log | grep $log_file_name_prefix`; do

    # remove \r that for some reason is at the end o.O
    log_file=$(echo $log_file | tr -d '\r')

    #echo $log_file

    log_line=$(grep SyncProgressStats /usr/local/crashplan/log/$log_file 2>/dev/null | grep -v Binary\ file | tail -1);

    if [ ! "$log_line" = "" ]; then
        percent=$(echo $log_line | sed "s/.*total=[0-9]*..//" | sed "s/%.*/%/");
        date_time=$(echo $log_line | sed "s/^.//" | sed "s/.INFO.*//")
        echo $percent, $date_time
        exit
    fi
done

echo false

