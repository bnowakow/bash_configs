#!/bin/bash

log_number=0;

while true; do

    #echo "log_number=$log_number";

    log_exists=$(sudo /usr/bin/su sup -c "cd /mnt/MargokPool/home/sup/code/crashplan-docker; vagrant ssh -c 'cd ~/docker-ubuntu-novnc-crashplan; docker exec crashplan ls /usr/local/crashplan/log/service.log.'$log_number' >/dev/null'" 2>/dev/null);

    if [ "$log_exists" = "" ]; then
        log_line=$(sudo /usr/bin/su sup -c "cd /mnt/MargokPool/home/sup/code/crashplan-docker; vagrant ssh -c 'cd ~/docker-ubuntu-novnc-crashplan; docker exec crashplan grep SyncProgressStats /usr/local/crashplan/log/service.log.'$log_number' | tail -1'" 2>/dev/null);

        if [ ! "$log_line" = "" ]; then
            percent=$(echo $log_line | sed "s/.*total=[0-9]*..//" | sed "s/%.*/%/");
            date_time=$(echo $log_line | sed "s/^.//" | sed "s/.INFO.*//")
            echo $percent, $date_time
            exit
        fi
    else
        echo false
        exit
    fi

let log_number=$log_number+1;
done

