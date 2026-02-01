#!/bin/bash -x

#https://gist.github.com/tree-s/1b2177bac1d8f2b70fac9e235a7f262c
host=transmission.localdomain.bnowakowski.pl
port=9091
user=transmission
pass=$(cat .transmission-password)


curl_transmission() {
    sessid=$(curl --connect-timeout 10 --max-time 15 --silent --anyauth --user $user:$pass "http://$host:$port/transmission/rpc" | sed 's/.*<code>//g;s/<\/code>.*//g')
    # TODO can below echo to standard error 2> ? to not affect function output
    #echo sessid=$sessid # remember that after uncommenting this script using this function will fail since output woulnt'd be only http code
    if [ "$sessid" = "" ]; then
        echo 0;
        return;
    fi
    #curl --connect-timeout 10 --max-time 15 -X GET --anyauth --user $user:$pass --header "$sessid" "http://$host:$port/transmission/web/"

    transmission_http_code=$(curl --connect-timeout 10 --max-time 15 -s -o /dev/null -w "%{http_code}" -X GET --anyauth --user $user:$pass --header "$sessid" "http://$host:$port/transmission/web/")
    echo $transmission_http_code
}

for try in `seq 1 3`; do
    echo try=$try;
    date;
    transmission_http_code=$(curl_transmission)
    echo transmission_http_code=$transmission_http_code
    if [ "$transmission_http_code" = "200" ]; then
        echo "transmission is up"
        exit # Comment while DEBUG
    else
        # TODO check 403 that might be returned when daemon is starting and then do longer sleep to give it a time to start?
        echo "transmission is down at try=$try"
    fi    
    sleep 10s; # Comment while DEBUG
done

proxmox_vm_id=600;

transmission_vm_boot_date_time_before_reboot=$(ssh -t $host "who -b")
echo transmission_vm_boot_date_time_before_reboot=$transmission_vm_boot_date_time_before_reboot;
date
ssh -t root@$host "reboot"
date
sleep 4m;
checks_number=0
checks_maximum_number=6
while true; do
    #transmission_vm_boot_date_time_after_reboot=$(timeout --kill-after=10s 5s ssh -t $host "who -b")
    transmission_vm_boot_date_time_after_reboot=$(timelimit -S 4 -s 6 -T 8 -t 10 ssh -t $host "who -b")
    if [ "$transmission_vm_boot_date_time_after_reboot" != "" ] && [ "$transmission_vm_boot_date_time_after_reboot" != "$transmission_vm_boot_date_time_before_reboot" ]; then 
        echo "booted";
        break;
    fi
    ((checks_number++))
    echo checks_number=$checks_number
    if [ $checks_number -ge $checks_maximum_number ]; then
        break;
    fi

    sleep 1m;
done

date

if [ $checks_number -ge $checks_maximum_number ]; then
    echo "didn't detect system up after reboot, reseting vm"
    # TODO add timeout and check if succecced 
    sudo qm reset $proxmox_vm_id
else
    echo "system booted after reboot";
fi




