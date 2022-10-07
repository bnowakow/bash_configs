#!/bin/bash

backup_dir="${1:-ovh}"

backup_prefix_dir="/mnt/MargokPool/archive/Backups";

last_backup_date=$(ls --full-time -t $backup_prefix_dir/$backup_dir/*tar* | head -1 | awk '{print $6}')
curent_date=$(date +%Y-%m-%d)

days_diff=$(( (`date -d $curent_date +%s` - `date -d $last_backup_date +%s`) / (24*3600) ));

echo $days_diff

