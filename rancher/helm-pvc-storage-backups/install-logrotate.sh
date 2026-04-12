#!/bin/bash

# Install logrotate configuration for PVC backup script
# This script installs the logrotate configuration to automatically rotate backup logs

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGROTATE_CONF="$SCRIPT_DIR/backup-pvc-logrotate.conf"
LOGROTATE_INSTALL_DIR="/etc/logrotate.d"
LOGROTATE_INSTALL_PATH="$LOGROTATE_INSTALL_DIR/pvc-backup"

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

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_status "failure" "This script must be run as root (use sudo)"
    exit 1
fi

# Check if logrotate configuration file exists
if [ ! -f "$LOGROTATE_CONF" ]; then
    print_status "failure" "Logrotate configuration file not found: $LOGROTATE_CONF"
    exit 1
fi

# Copy logrotate configuration to system directory
print_status "" "Installing logrotate configuration..."
cp "$LOGROTATE_CONF" "$LOGROTATE_INSTALL_PATH"
chmod 644 "$LOGROTATE_INSTALL_PATH"

# Verify installation
if logrotate -d "$LOGROTATE_INSTALL_PATH" > /dev/null 2>&1; then
    print_status "success" "Logrotate configuration installed successfully at $LOGROTATE_INSTALL_PATH"
    print_status "" "Logs will be rotated daily with a 30-day retention period"
    exit 0
else
    print_status "failure" "Logrotate configuration validation failed"
    exit 1
fi
