#!/bin/bash

# Install logrotate configuration for PVC backup script
# This script installs the logrotate configuration to automatically rotate backup logs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGROTATE_CONF="$SCRIPT_DIR/backup-pvc-logrotate.conf"
LOGROTATE_INSTALL_DIR="/etc/logrotate.d"
LOGROTATE_INSTALL_PATH="$LOGROTATE_INSTALL_DIR/pvc-backup"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: This script must be run as root (use sudo)" >&2
    exit 1
fi

# Check if logrotate configuration file exists
if [ ! -f "$LOGROTATE_CONF" ]; then
    echo "ERROR: Logrotate configuration file not found: $LOGROTATE_CONF" >&2
    exit 1
fi

# Copy logrotate configuration to system directory
echo "Installing logrotate configuration..."
cp "$LOGROTATE_CONF" "$LOGROTATE_INSTALL_PATH"
chmod 644 "$LOGROTATE_INSTALL_PATH"

# Verify installation
if logrotate -d "$LOGROTATE_INSTALL_PATH" > /dev/null 2>&1; then
    echo "✓ SUCCESS: Logrotate configuration installed successfully at $LOGROTATE_INSTALL_PATH"
    echo "Logs will be rotated daily with a 30-day retention period"
    exit 0
else
    echo "✗ FAILURE: Logrotate configuration validation failed" >&2
    exit 1
fi
