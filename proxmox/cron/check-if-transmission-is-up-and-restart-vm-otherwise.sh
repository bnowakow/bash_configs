#!/bin/bash

#https://gist.github.com/tree-s/1b2177bac1d8f2b70fac9e235a7f262c
host=transmission.localdomain.bnowakowski.pl
port=9091
user=transmission
pass=$(cat .transmission-password)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
LIGHT_BLUE='\033[94m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    
    case $status in
        success)
            echo -e "${GREEN}✓ SUCCESS:${NC} $message"
            ;;
        failure)
            echo -e "${RED}✗ FAILURE:${NC} $message"
            ;;
        *)
            echo -e "${YELLOW}⚠ INFO:${NC} $message"
            ;;
    esac
}


curl_transmission() {
    sessid=$(curl --connect-timeout 10 --max-time 15 --silent --anyauth --user $user:$pass "http://$host:$port/transmission/rpc" | sed 's/.*<code>//g;s/<\/code>.*//g')
    # TODO can below echo to standard error 2> ? to not affect function output
    #echo sessid=$sessid # remember that after uncommenting this script using this function will fail since output woulnt'd be only http code
    if [ "$sessid" = "" ]; then
        echo 0;
        return;
    fi
    # TODO can below echo to standard error 2> ? to not affect function output
    #curl --connect-timeout 10 --max-time 15 -X GET --anyauth --user $user:$pass --header "$sessid" "http://$host:$port/transmission/web/" # remember that after uncommenting this script using this function will fail since output woulnt'd be only http code

    transmission_http_code=$(curl --connect-timeout 10 --max-time 15 -s -o /dev/null -w "%{http_code}" -X GET --anyauth --user $user:$pass --header "$sessid" "http://$host:$port/transmission/web/")
    echo $transmission_http_code
}

for try in `seq 1 $transmission_check_attempts`; do
    #echo try=$try;
    echo -e "transmission HTTP API check attempt=${LIGHT_BLUE}$try/${transmission_check_attempts}${NC}"
    date;
    transmission_http_code=$(curl_transmission)
    #echo transmission_http_code=$transmission_http_code
    if [ "$transmission_http_code" = "200" ]; then
        print_status "success" "transmission is up"
        exit # Comment while DEBUG
    else
        # TODO check 403 that might be returned when daemon is starting and then do longer sleep to give it a time to start?
        print_status "failure" "transmission is down at try=${LIGHT_BLUE}$try${NC}"
    fi    
    sleep $transmission_check_interval; # Comment while DEBUG
done

proxmox_vm_id=600;

# Sleep duration settings
reboot_wait_time=4m
check_wait_time=1m
transmission_check_interval=10s

# Attempt settings
transmission_check_attempts=3
reboot_check_maximum_number=6

transmission_vm_boot_date_time_before_reboot=$(ssh -t $host "who -b" 2>&1)
ssh_exit_code=$?
if [ "$transmission_vm_boot_date_time_before_reboot" = "" ] && [ $ssh_exit_code -ne 0 ]; then
    print_status "failure" "SSH command failed with exit code $ssh_exit_code: ssh -t $host \"who -b\""
elif echo "$transmission_vm_boot_date_time_before_reboot" | grep -q "No route to host"; then
    print_status "failure" "Cannot connect to VM via SSH running 'who -b': No route to host"
    transmission_vm_boot_date_time_before_reboot=""
else
    echo transmission_vm_boot_date_time_before_reboot=$transmission_vm_boot_date_time_before_reboot;
fi
date
ssh_output=$(ssh -t root@$host "reboot" 2>&1)
if echo "$ssh_output" | grep -q "No route to host"; then
    print_status "failure" "Cannot connect to VM via SSH running 'reboot' as root: No route to host"
else
    echo "$ssh_output"
fi
date
print_status "" "Waiting $reboot_wait_time for VM to reboot..."
sleep $reboot_wait_time;
checks_number=0
checks_maximum_number=$reboot_check_maximum_number
while true; do
    # for some reason when timeout was used it didn't finished it time (that was fixed after adding --kill-after, but after that ssh didn't connect eventhough at the same time in different terminal ssh was responding
    #transmission_vm_boot_date_time_after_reboot=$(timeout --kill-after=10s 5s ssh -t $host "who -b")
    transmission_vm_boot_date_time_after_reboot=$(timelimit -S 4 -s 6 -T 8 -t 10 ssh -t $host "who -b" 2>&1)
    if [ "$transmission_vm_boot_date_time_after_reboot" = "" ]; then
        print_status "failure" "SSH command failed: ssh -t $host \"who -b\""
        transmission_vm_boot_date_time_after_reboot=""
    elif echo "$transmission_vm_boot_date_time_after_reboot" | grep -q "No route to host"; then
        print_status "failure" "Cannot connect to VM via SSH running 'who -b': No route to host"
        transmission_vm_boot_date_time_after_reboot=""
    fi
    if [ "$transmission_vm_boot_date_time_after_reboot" != "" ] && [ "$transmission_vm_boot_date_time_after_reboot" != "$transmission_vm_boot_date_time_before_reboot" ]; then 
        print_status "success" "booted"
        break;
    fi
    ((checks_number++))
    echo -e "reboot check attempt=${LIGHT_BLUE}$checks_number/${checks_maximum_number}${NC}"
    if [ $checks_number -ge $checks_maximum_number ]; then
        break;
    fi
    print_status "" "Waiting $check_wait_time before next check (${LIGHT_BLUE}${checks_number}/${checks_maximum_number}${NC})..."
    sleep $check_wait_time;
done

date

if [ $checks_number -ge $checks_maximum_number ]; then
    print_status "failure" "didn't detect system up after reboot, reseting vm"
    reset_output=$(sudo qm reset $proxmox_vm_id 2>&1)
    if echo "$reset_output" | grep -q "not running"; then
        print_status "" "VM $proxmox_vm_id not running, starting VM"
        sudo qm start $proxmox_vm_id
    else
        print_status "" "VM reset attempted: $reset_output"
    fi
else
    print_status "success" "system booted after reboot"
fi




