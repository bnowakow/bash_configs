#!/bin/bash

log_file_name_prefix="service.log";

for log_file in `ls -1t /usr/local/crashplan/log | grep $log_file_name_prefix`; do

    # remove \r that for some reason is at the end o.O
    log_file=$(echo $log_file | tr -d '\r')

    #echo $log_file; # DEBUG

    log_line=$(grep files\ completed /usr/local/crashplan/log/$log_file | grep HISTORY | tail -1);
    
    if [ ! "$log_line" = "" ]; then
        stats=$(echo $log_line | sed "s/^.*completed in//" | sed "s/.found.*//");
        date_time=$(echo $log_line | sed "s/^.//" | sed "s/.INFO.*//")
        echo $stats, $date_time
        exit
    fi
done

echo false

