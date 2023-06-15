#!/bin/bash

log_file_name_prefix="service.log";

for log_file in `ls -1t /usr/local/crashplan/log | grep $log_file_name_prefix`; do

    # remove \r that for some reason is at the end o.O
    log_file=$(echo $log_file | tr -d '\r')

    #echo log_file=$log_file # DEBUG

    log_line=$(grep history /usr/local/crashplan/log/$log_file | grep -v Binary\ file | tail -1);

    #echo -e "\t"log_line=$log_line # DEBUG

    if [ ! "$log_line" = "" ]; then
        stats=$(echo $log_line | sed "s/^.*Completed file/Completed file/" | sed "s/FileItem.*history.log.[0-9]*,//" | sed "s/duration=[0-9]* ms;/duration: /" | sed "s/readDuration=[0-9]* ms;/readDuration: /" | sed "s/sendDuration=[0-9]* ms;/sendDuration: /");
        date_time=$(echo $log_line | sed "s/^.//" | sed "s/INFO.*//")
        echo $stats 
        echo -n \; $date_time
        exit
    fi
done

echo false

