#!/bin/bash

backup_dir="/mnt/MargokPool/archive/Backups/rancher/storage"
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
underscore="_"

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
    
    local source_dir="$pvc_dir_prefix/$pvc_dir_middle$namespace-$app$underscore$pvc_dir_suffix"
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

# Define individual backup targets as an array
# Format: "app:pvc_dir_middle:pvc_dir_suffix"
backup_targets=(
    "adguard:pvc-88701eb6-263f-47ca-8c8c-c8310a3bfdda_:adguard-home-data"
    "adguard-home:pvc-ff810ac9-1f85-49a2-ac92-10a1806f0e50_:adguard-home-config"
    "bazarr:pvc-81428f12-9714-4d85-99f8-2617655be696_:bazarr-config"
    "ddclient:pvc-277a068b-f588-4dec-866b-f730766fa910_:ddclient-config"
    "docker-mailserver:pvc-366e595d-ce9b-4029-8054-6dee5a22dc54_:docker-mailserver-mail-data"
    "docker-mailserver:pvc-625fcc7a-8680-43f3-ad19-3be6b6b6259f_:docker-mailserver-mail-state"
    "docker-mailserver:pvc-cfb72d39-4cf6-43ce-b997-bd5f59f3d72c_:docker-mailserver-mail-log"
    "docker-mailserver:pvc-e1186a18-2f87-45e3-b284-d58f09689a91_:docker-mailserver-mail-config"
    "filebot:pvc-bfdecbc8-82db-4c3a-ab47-ddf96905d5fc_:filebot-config"
    "homer:pvc-80dc3cac-61fb-4222-849b-2197bac3a9df_:-config"
    "jellyseerr:pvc-59cd6a11-8793-43e1-965a-28edd3257d7a_:jellyseerr-config"
    "prowlarr:pvc-179babac-ae59-4484-bbf5-2767ed088d5a_:prowlarr-config"
    "radarr:pvc-2df6a22e-ccef-46cd-a46d-0653232a47e3_:radarr-config"
    "smokeping:pvc-518bdbcd-48e8-46ec-896c-81b1227f4d18_:smokeping-data"
    "smokeping:pvc-ae06abe7-9b40-4f7d-9366-880db6647abc_:smokeping-config"
    "sonarr:pvc-b5811237-c692-4e2d-aa39-fc61f56fe0a8_:sonarr-config"
    "scrutiny:pvc-36b30dbf-47e6-4a93-b193-b7b576b26949_:scrutiny-config"
    "scrutiny:pvc-da5e04e3-c415-498a-b777-e7ad9f1f636f_:scrutiny-influxdb"
    "youtubedl-material:pvc-02735a71-190c-4f5e-bd43-7bd82ca7a062_:-appdata"
    "zabbix:pvc-7bb141a9-5e9b-4bd1-89b2-d4ab28b7a7d5_:postgresql-data-zabbix-postgresql-0"
)

# Iterate through all backup targets and backup each one
for target in "${backup_targets[@]}"; do
    IFS=':' read -r app pvc_dir_middle pvc_dir_suffix <<< "$target"
    
    backup_pvc "$pvc_dir_middle" "$app" "$pvc_dir_suffix"
    if [ $? -ne 0 ]; then
        echo "Backup of $app failed" >&2
    fi
done



