#!/bin/bash

backup_dir="/home/sup/code/bash_configs/rancher/helm-pvc-storage-backups"
pvc_dir_prefix="/var/lib/rancher/k3s/storage"
log_dir="$backup_dir/logs"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}ERROR${NC}: This script must be run as root (use sudo)" >&2
    exit 1
fi

namespace="apps"

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

# Function to backup a PVC with error handling
backup_pvc() {
    local pvc_dir_middle=$1
    local app=$2
    local pvc_dir_suffix=$3
    
    local source_dir="$pvc_dir_prefix/$pvc_dir_middle$namespace-$app$underscore$app$pvc_dir_suffix"
    local destination_dir="$backup_dir/$app"
    local log_file="$log_dir/backup-${app}-$(date +%Y%m%d-%H%M%S).log"
    
    # Create log directory if it doesn't exist
    mkdir -p "$log_dir"
    
    # Check if source directory exists
    if [ ! -d "$source_dir" ]; then
        print_status "failure" "Source directory does not exist: $source_dir"
        echo "ERROR: Source directory does not exist: $source_dir" >> "$log_file"
        return 1
    fi
    
    # Create destination directory if it doesn't exist
    if ! mkdir -p "$destination_dir"; then
        print_status "failure" "Failed to create destination directory: $destination_dir"
        echo "ERROR: Failed to create destination directory: $destination_dir" >> "$log_file"
        return 1
    fi
    
    # Run rsync and redirect output to log file
    rsync -a --progress "$source_dir" "$destination_dir" >> "$log_file" 2>&1
    
    local rsync_exit_code=$?
    if [ $rsync_exit_code -eq 0 ]; then
        print_status "success" "Backed up $app (log: $log_file)"
        return 0
    elif [ $rsync_exit_code -eq 23 ] || [ $rsync_exit_code -eq 24 ]; then
        # Exit codes 23 and 24 are partial transfers (some files couldn't be transferred)
        print_status "" "Backup of $app completed with warnings (exit code: $rsync_exit_code, log: $log_file)"
        return 0
    else
        print_status "failure" "Backup of $app failed (exit code: $rsync_exit_code, log: $log_file)"
        return 1
    fi
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



