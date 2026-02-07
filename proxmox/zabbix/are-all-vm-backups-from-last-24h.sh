#!/bin/bash

# on first run from particular user you need to accept fingerprint twice

export PBS_PASSWORD="$(cat .pbs-password)"; 

any_backup_have_too_old_backup=false

# skipping vm_id = 300 which is home assistant supervised on debian which was migrated to HAOS which is vm_id = 350
for vm_id in $(proxmox-backup-client list --repository backup@pbs@proxmox-backup-server.tailscale.bnowakowski.pl:margok-pbs-nfs --output-format json-pretty | jq ".[].\"backup-id\"" | grep -v '"300"'); do
    #echo vm_id=$vm_id;
    last_update=$(proxmox-backup-client list --repository backup@pbs@proxmox-backup-server.tailscale.bnowakowski.pl:margok-pbs-nfs --output-format json-pretty | jq "map(select(.\"backup-id\" == $vm_id))" | jq ".[0].\"last-backup\"")
    #echo last_update=$last_update
    seconds_since_last_backup=$(($(date +%s) - $last_update))
    numer_of_seconds_in_a_day=86400
    #echo seconds_since_last_backup=$seconds_since_last_backup
    if [ ! "$seconds_since_last_backup" -le "$numer_of_seconds_in_a_day" ]; then
        if [ "$any_backup_have_too_old_backup" == "false" ]; then
            any_backup_have_too_old_backup=true;
            echo -n "false,$vm_id"
        else
            echo -n ",$vm_id"
        fi
    fi
    #exit
done

if [ "$any_backup_have_too_old_backup" == "false" ]; then
    echo true;
fi


