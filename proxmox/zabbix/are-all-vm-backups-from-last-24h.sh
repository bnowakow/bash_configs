#!/bin/bash

# on first run from particular user you need to accept fingerprint twice

cd /etc/zabbix/zabbix_agent2.d/bash_configs/proxmox/zabbix || exit 1
export PBS_PASSWORD="$(cat .pbs-password)"

repository="backup@pbs@proxmox-backup-server.tailscale.bnowakowski.pl:margok-pbs-nfs"
number_of_seconds_in_a_day=86400
now=$(date +%s)

# These VMs do not need daily backup checks.
ignored_backup_ids='["800", "900"]'
backup_list_error=$(mktemp)
trap 'rm -f "$backup_list_error"' EXIT

if ! backups_json=$(proxmox-backup-client list --repository "$repository" --output-format json 2>"$backup_list_error"); then
    error_message=$(tr '\n' ' ' < "$backup_list_error")
    if [[ "$error_message" == *"unable to open chunk store"* ]]; then
        echo false,datastore-unavailable
    else
        echo false,proxmox-backup-client-list-error
    fi
    exit 0
fi

if ! missing_groups=$(
    jq -r \
        --argjson now "$now" \
        --argjson max_age "$number_of_seconds_in_a_day" \
        --argjson ignored_backup_ids "$ignored_backup_ids" \
        '
        # Restores/migrations stay within the same hundred range, e.g. 300/350/351.
        def group_id:
            if (."backup-id" | test("^[0-9][0-9][0-9]$")) then
                (."backup-id" | .[0:1]) + "xx"
            else
                ."backup-id"
            end;

        [
            .[]
            | select(."backup-id" as $backup_id | $ignored_backup_ids | index($backup_id) | not)
            | {
                group_id: group_id,
                backup_id: ."backup-id",
                is_recent: (($now - ."last-backup") <= $max_age)
            }
        ]
        | group_by(.group_id)
        | map(select(any(.is_recent) | not))
        | map(
            map(.backup_id)
            | sort
            | join("/")
        )
        | join(",")
        ' <<< "$backups_json"
); then
    echo false,jq-error
    exit 0
fi

if [ -z "$missing_groups" ]; then
    echo true
else
    echo "false,$missing_groups"
fi
