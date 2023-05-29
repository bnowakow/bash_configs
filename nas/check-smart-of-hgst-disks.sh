#!/bin/bash

for disk in /dev/sd*; do
    # process only disks not partitions
    echo $disk | grep -v [0-9] > /dev/null;
    if [ $? == 1 ]; then
        continue;
    fi;
    
    # process only HGST disks
    sudo smartctl -a $disk | grep "Device Model" | grep HGST > /dev/null
    if [ $? == 1 ]; then
        continue;
    fi;


    sudo hddtemp $disk;
    
    #echo $disk;
    #sudo smartctl -a $disk | grep "Device Model"
    
    sudo smartctl -a $disk | grep Power_On_Hours
    sudo smartctl -a $disk | grep UDMA_CRC_Error_Count
    sudo smartctl -a $disk | grep self-assessment
    #sudo smartctl -a $disk | grep Celsius | sed 's/[^-]*//'
 
    #sudo hdparm -tTv $disk | grep Timing # with cache
    sudo hdparm -tv $disk | grep Timing
   
    echo
done
