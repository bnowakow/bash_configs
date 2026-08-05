#!/bin/bash

proxmox_vm_id=600;

#https://gist.github.com/tree-s/1b2177bac1d8f2b70fac9e235a7f262c
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
password_file="$script_dir/.transmission-password"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
LIGHT_BLUE='\033[94m'
NC='\033[0m' # No Color

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

get_vm_boot_time() {
    local ssh_target=$1
    local command_output
    local command_exit_code

    command_output=$(timelimit -S 4 -s 6 -T 8 -t 10 ssh -o BatchMode=yes -t "$ssh_target" "who -b" 2>&1)
    command_exit_code=$?

    if [ $command_exit_code -ne 0 ]; then
        if echo "$command_output" | grep -q "No route to host"; then
            print_status "failure" "Cannot connect to VM via SSH running 'who -b': No route to host"
        else
            print_status "failure" "SSH command failed with exit code $command_exit_code: ssh -o BatchMode=yes -t $ssh_target \"who -b\""
        fi
        return 1
    fi

    if ! echo "$command_output" | grep -q "system boot"; then
        print_status "failure" "Unexpected output from ssh -o BatchMode=yes -t $ssh_target \"who -b\": $command_output"
        return 1
    fi

    printf '%s\n' "$command_output"
    return 0
}

validate_proxmox_vm_id() {
    local qm_list_output

    if ! command -v qm >/dev/null 2>&1; then
        print_status "failure" "missing required command: qm"
        exit 1
    fi

    qm_list_output="$(qm list 2>&1)"
    if ! printf '%s\n' "$qm_list_output" | awk 'NR > 1 {print $1}' | grep -x -q "$proxmox_vm_id"; then
        print_status "failure" "configured Proxmox VM ID does not exist: $proxmox_vm_id"
        print_status "" "Available VMs from 'qm list':"
        printf '%s\n' "$qm_list_output"
        exit 1
    fi
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_status "failure" "this script must be run as root"
        exit 1
    fi
}

ensure_root_ssh_key_access() {
    local ssh_target="root@$host"
    local ssh_output
    local ssh_exit_code

    print_status "" "Checking SSH key access to $ssh_target"
    ssh_output=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$ssh_target" "true" 2>&1)
    ssh_exit_code=$?
    if [ $ssh_exit_code -eq 0 ]; then
        print_status "success" "SSH key access to $ssh_target works"
        return 0
    fi

    if echo "$ssh_output" | grep -q "No route to host"; then
        print_status "failure" "Cannot connect to VM via SSH while checking key auth: No route to host"
        exit 1
    fi

    if echo "$ssh_output" | grep -q "port 22: Connection timed out"; then
        print_status "" "SSH connection to $ssh_target timed out; continuing so the Proxmox reboot fallback can run"
        return 0
    fi

    print_status "failure" "SSH key access to $ssh_target does not work: $ssh_output"
    print_status "" "Configure key-based SSH for root@$host before running this script unattended"
    exit 1
}
if [ ! -f "$password_file" ]; then
    print_status "failure" "missing Transmission password file: $password_file" >&2
    print_status "" "Create it based on: $script_dir/.transmission-password.sample" >&2
    exit 1
fi

host=transmission.localdomain.bnowakowski.pl
port=9091
user=transmission
pass=$(cat "$password_file")

# Sleep duration settings
reboot_wait_time=4m
check_wait_time=1m
transmission_check_interval=10s
internet_check_urls=(
    https://www.google.com/generate_204
    https://www.cloudflare.com/cdn-cgi/trace
    https://github.com/
)

# Attempt settings
transmission_check_attempts=3
reboot_check_maximum_number=6

require_root
validate_proxmox_vm_id
ensure_root_ssh_key_access

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

check_transmission_tracker_connectivity() {
    local rpc_response
    local tracker_summary

    if ! command -v jq >/dev/null 2>&1; then
        print_status "" "jq is not installed; skipping Transmission tracker check"
        return 0
    fi

    rpc_response=$(curl --connect-timeout 10 --max-time 15 --silent --show-error \
        --anyauth --user "$user:$pass" \
        --header "$sessid" \
        --header 'Content-Type: application/json' \
        --data '{"method":"torrent-get","arguments":{"fields":["name","trackerStats"]}}' \
        "http://$host:$port/transmission/rpc" 2>&1)

    if [ $? -ne 0 ]; then
        print_status "" "could not query Transmission tracker status"
        return 0
    fi

    tracker_summary=$(printf '%s\n' "$rpc_response" | jq -r '
        [.arguments.torrents[]?.trackerStats[]? |
          select(.lastAnnounceSucceeded == true or .lastAnnounceResult != null)] |
        if length == 0 then "no tracker announcements available"
        else
          ([.[] | select(.lastAnnounceSucceeded == true)] | length | tostring)
          + " successful tracker announcement(s), " + (length | tostring) + " tracker result(s)"
        end
    ' 2>/dev/null)

    if [ -n "$tracker_summary" ]; then
        print_status "" "Transmission tracker status: $tracker_summary"
    else
        print_status "" "could not parse Transmission tracker status"
    fi
    return 0
}

check_vm_internet_connectivity() {
    local ssh_output
    local ssh_exit_code
    local internet_check_url
    local failed_urls=""

    for internet_check_url in "${internet_check_urls[@]}"; do
        ssh_output=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "root@$host" \
            "curl --connect-timeout 5 --max-time 10 --fail --silent --show-error '$internet_check_url' >/dev/null" 2>&1)
        ssh_exit_code=$?

        if [ $ssh_exit_code -eq 0 ]; then
            print_status "success" "VM can connect to the Internet ($internet_check_url)"
            return 0
        fi

        failed_urls="$failed_urls $internet_check_url"
    done

    print_status "failure" "VM cannot connect to the Internet; all checks failed:$failed_urls"
    print_status "" "Last connectivity-check error: $ssh_output"
    return 1
}

for try in `seq 1 $transmission_check_attempts`; do
    #echo try=$try;
    echo -e "transmission HTTP API check attempt=${LIGHT_BLUE}$try/${transmission_check_attempts}${NC}"
    date;
    transmission_http_code=$(curl_transmission)
    #echo transmission_http_code=$transmission_http_code
    if [ "$transmission_http_code" = "200" ]; then
        print_status "success" "transmission RPC is up"
        check_transmission_tracker_connectivity
        if check_vm_internet_connectivity; then
            print_status "success" "Transmission and VM connectivity checks passed"
            exit # Comment while DEBUG
        fi
        print_status "failure" "Transmission responds, but VM connectivity check failed"
    else
        # TODO check 403 that might be returned when daemon is starting and then do longer sleep to give it a time to start?
        print_status "failure" "transmission is down at try=${LIGHT_BLUE}$try${NC}"
    fi    
    print_status "" "Sleeping $transmission_check_interval before next transmission HTTP API check"
    sleep $transmission_check_interval; # Comment while DEBUG
done

if transmission_vm_boot_date_time_before_reboot=$(get_vm_boot_time "root@$host"); then
    echo transmission_vm_boot_date_time_before_reboot=$transmission_vm_boot_date_time_before_reboot;
else
    transmission_vm_boot_date_time_before_reboot=""
fi
date
ssh_output=$(ssh -o BatchMode=yes -t root@$host "reboot" 2>&1)
ssh_exit_code=$?
if [ $ssh_exit_code -ne 0 ] && echo "$ssh_output" | grep -q "port 22: Connection timed out"; then
    print_status "failure" "Cannot connect to VM via SSH running 'reboot' as root: port 22 connection timed out"
    print_status "" "Issuing reboot through Proxmox for VM $proxmox_vm_id"
    reboot_output=$(qm reboot "$proxmox_vm_id" 2>&1)
    reboot_exit_code=$?
    if [ $reboot_exit_code -ne 0 ]; then
        print_status "failure" "Proxmox reboot failed with exit code $reboot_exit_code: $reboot_output"
    else
        print_status "" "Proxmox reboot issued: $reboot_output"
    fi
elif [ $ssh_exit_code -ne 0 ] && echo "$ssh_output" | grep -q "No route to host"; then
    print_status "failure" "Cannot connect to VM via SSH running 'reboot' as root: No route to host"
elif [ $ssh_exit_code -ne 0 ]; then
    print_status "failure" "SSH command failed with exit code $ssh_exit_code: ssh -o BatchMode=yes -t root@$host \"reboot\""
else
    echo "$ssh_output"
fi
date
print_status "" "Waiting $reboot_wait_time for VM to reboot..."
sleep $reboot_wait_time;
checks_number=0
checks_maximum_number=$reboot_check_maximum_number
while true; do
    if ! transmission_vm_boot_date_time_after_reboot=$(get_vm_boot_time "root@$host"); then
        transmission_vm_boot_date_time_after_reboot=""
    elif [ "$transmission_vm_boot_date_time_after_reboot" != "$transmission_vm_boot_date_time_before_reboot" ]; then 
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
