#!/bin/bash
set -u
set -o pipefail

# when backup errors during, doesn't finish and can't start new one: https://forum.vestacp.com/viewtopic.php?f=10&t=16357

remote_host=ovh.bnowakowski.pl
remote_dir="/backup"

local_dir_prefix="/mnt/MargokPool/archive/Backups"

number_of_backpus_to_keep=30
let number_of_backpus_to_keep=$number_of_backpus_to_keep+1;

rsync_max_attempts=3
rsync_retry_sleep_seconds=300
exit_status=0

if [ "${FORCE_COLOR:-0}" = "1" ] || [ -t 1 ]; then
    color_red=$'\033[31m'
    color_green=$'\033[32m'
    color_yellow=$'\033[33m'
    color_reset=$'\033[0m'
else
    color_red=''
    color_green=''
    color_yellow=''
    color_reset=''
fi

log_success() {
    echo "${color_green}$*${color_reset}"
}

log_warning() {
    echo "${color_yellow}$*${color_reset}" >&2
}

log_error() {
    echo "${color_red}$*${color_reset}" >&2
}

download_backup() {
    local remote_path="$1"
    local local_dir="$2"
    local attempt=1
    local rsync_status=0

    while [ "$attempt" -le "$rsync_max_attempts" ]; do
        echo "Starting rsync attempt $attempt/$rsync_max_attempts: $remote_host:$remote_path -> $local_dir"
        rsync -vvv --partial --progress --rsh=ssh -r --remove-source-files "$remote_host:$remote_path" "$local_dir"
        rsync_status=$?

        if [ "$rsync_status" -eq 0 ]; then
            log_success "SUCCESS: rsync succeeded on attempt $attempt: $remote_path"
            return 0
        fi

        log_error "ERROR: rsync failed with exit code $rsync_status on attempt $attempt/$rsync_max_attempts: $remote_path"

        if [ "$attempt" -lt "$rsync_max_attempts" ]; then
            log_warning "WARNING: retrying in $rsync_retry_sleep_seconds seconds..."
            sleep "$rsync_retry_sleep_seconds"
        fi

        attempt=$((attempt + 1))
    done

    log_error "ERROR: rsync failed after $rsync_max_attempts attempts: $remote_path"
    return "$rsync_status"
}

newest_file_name() {
    local dir="$1"
    local pattern="$2"

    find "$dir" -maxdepth 1 -type f -name "$pattern" -printf '%T@ %f\n' | sort -nr | head -n 1 | cut -d' ' -f2-
}

user_names=( sup admin );
for user_name in "${user_names[@]}"; do
    echo $user_name;
    local_dir="$local_dir_prefix/ovh-$user_name"
    remote_path="$remote_dir/$user_name*.tar";
    mkdir -p "$local_dir"
    
    # download new backup
    # -e "ssh -i $HOME/.ssh/id_rsa"
    if ! download_backup "$remote_path" "$local_dir"; then
        log_error "ERROR: skipping rotation for $user_name because backup download failed"
        exit_status=1
        continue
    fi

    # rotate old backups
    number_of_backup_files=$(find "$local_dir" -maxdepth 1 -type f -name "$user_name*" | wc -l);
    if [ $number_of_backup_files -gt $number_of_backpus_to_keep ]; then
        find "$local_dir" -maxdepth 1 -type f -name "$user_name*" -printf '%T@ %p\n' | sort -nr | tail -n +$number_of_backpus_to_keep | cut -d' ' -f2- | xargs -r rm;
    fi

    # rotate backup for crashplan (it holds only 1 backup out of 10 to not send too much data)
    local_one_file_backup_dir="$local_dir_prefix/one_file_backup/ovh-$user_name"
    mkdir -p "$local_one_file_backup_dir";
    one_file_backup_needs_to_be_copied=0;
    if [ "$(find "$local_one_file_backup_dir" -maxdepth 1 -type f | wc -l)" -gt 0 ]; then
        # backup for crashplan already exists
        current_one_file_backup=$(newest_file_name "$local_one_file_backup_dir" '*')
        if [ "$(find "$local_dir" -name "$current_one_file_backup" | wc -l)" -eq 0  ]; then
            find "$local_one_file_backup_dir" -maxdepth 1 -type f -delete;
            one_file_backup_needs_to_be_copied=1
        fi
    else
        # backup for crashplan doesn't exist
        one_file_backup_needs_to_be_copied=1
    fi

    if [ $one_file_backup_needs_to_be_copied -eq 1 ]; then
        newest_backup=$(newest_file_name "$local_dir" "$user_name*")
        if [ -n "$newest_backup" ]; then
            if ! cp "$local_dir/$newest_backup" "$local_one_file_backup_dir"; then
                log_error "ERROR: failed to copy $local_dir/$newest_backup to $local_one_file_backup_dir"
                exit_status=1
            fi
        else
            log_error "ERROR: no local backup found for $user_name after successful rsync"
            exit_status=1
        fi
    fi
done

exit "$exit_status"
