#!/bin/bash

log_line=$(sudo /usr/bin/su sup -c "cd /mnt/MargokPool/home/sup/code/crashplan-docker; vagrant ssh -c 'cd ~/docker-ubuntu-novnc-crashplan; docker exec crashplan grep SyncProgressStats /usr/local/crashplan/log/service.log.0 | tail -1'" 2>/dev/null);

percent=$(echo $log_line | sed "s/.*total=[0-9]*..//" | sed "s/%.*/%/");
date_time=$(echo $log_line | sed "s/^.//" | sed "s/.INFO.*//")
echo $percent, $date_time


