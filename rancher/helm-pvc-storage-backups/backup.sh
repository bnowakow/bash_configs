#!/bin/bash

# TODO make sure runs as root

backup_dir="/home/sup/code/bash_configs/rancher/helm-pvc-storage-backups"
pvc_dir_prefix="/var/lib/rancher/k3s/storage"

namespace="apps"
underscore="_"

# Function to backup a PVC with error handling
backup_pvc() {
    local pvc_dir_middle=$1
    local app=$2
    local pvc_dir_suffix=$3
    
    local source_dir="$pvc_dir_prefix/$pvc_dir_middle$namespace-$app$underscore$app$pvc_dir_suffix"
    local destination_dir="$backup_dir/$app"
    
    # Check if source directory exists
    if [ ! -d "$source_dir" ]; then
        echo "ERROR: Source directory does not exist: $source_dir" >&2
        return 1
    fi
    
    # Create destination directory if it doesn't exist
    if ! mkdir -p "$destination_dir"; then
        echo "ERROR: Failed to create destination directory: $destination_dir" >&2
        return 1
    fi
    
    # Run rsync and check exit code
    echo "Backing up $app from $source_dir to $destination_dir..."
    rsync -a -v --progress "$source_dir" "$destination_dir"
    
    local rsync_exit_code=$?
    if [ $rsync_exit_code -ne 0 ]; then
        echo "ERROR: rsync failed for $app with exit code $rsync_exit_code" >&2
        return 1
    fi
    
    echo "Successfully backed up $app"
    return 0
}

# Define apps to backup as an associative array
# Format: [app_name]="pvc_dir_middle:pvc_dir_suffix"
declare -A apps_to_backup
apps_to_backup["homer"]="pvc-80dc3cac-61fb-4222-849b-2197bac3a9df_:-config"
apps_to_backup["youtubedl-material"]="pvc-02735a71-190c-4f5e-bd43-7bd82ca7a062_:-appdata"

# Iterate through all apps and backup each one
for app in "${!apps_to_backup[@]}"; do
    IFS=':' read -r pvc_dir_middle pvc_dir_suffix <<< "${apps_to_backup[$app]}"
    
    backup_pvc "$pvc_dir_middle" "$app" "$pvc_dir_suffix"
    if [ $? -ne 0 ]; then
        echo "Backup of $app failed" >&2
    fi
done



