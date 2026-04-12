# PVC Storage Backups

Backs up Kubernetes PVC data from Rancher k3s storage to local directories with automatic log rotation.

## Setup

### 1. Install Logrotate Configuration (One-time setup)

```bash
sudo ./install-logrotate.sh
```

This installs the logrotate configuration to automatically rotate, compress, and retain backup logs for 30 days.

## Running Backups

### Run the backup script

```bash
sudo ./backup.sh
```

The script will:
- Backup configured applications from k3s PVC storage
- Validate source and destination directories
- Log all rsync operations to timestamped log files
- Display colored status summaries (green=success, red=failure, yellow=warnings)

## Configuration

Edit the `apps_to_backup` associative array in `backup.sh` to add or remove applications:

```bash
apps_to_backup["app-name"]="pvc-uuid_:suffix"
```

## Logs

Backup logs are stored in `logs/` directory with the format: `backup-{app}-{YYYYMMDD-HHMMSS}.log`
