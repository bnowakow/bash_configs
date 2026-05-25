#!/bin/bash

# on first run from particular user you need to accept fingerprint twice

cd /home/sup/code/bash_configs/proxmox/zabbix || exit 1
export PBS_PASSWORD="$(cat .pbs-password)"

repository="backup@pbs@proxmox-backup-server.tailscale.bnowakowski.pl:margok-pbs-nfs"
number_of_seconds_in_a_day=86400
now=$(date +%s)

# These VMs do not need daily backup checks.
ignored_backup_ids='["800", "900"]'

if ! backups_json=$(proxmox-backup-client list --repository "$repository" --output-format json 2>/dev/null); then
    echo false,proxmox-backup-client-list-error
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
