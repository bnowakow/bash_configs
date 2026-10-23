#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$EUID" -ne 0 ]; then
  exec sudo bash "$script_dir/install-cron.sh"
fi
if [ ! -x "$script_dir/upgrade.sh" ]; then
  echo "Missing executable: $script_dir/upgrade.sh" >&2
  exit 1
fi
# Cron interprets percent signs even inside shell quotes.
if [[ "$script_dir" == *'%'* || "$script_dir" == *'"'* || "$script_dir" == *'$'* || "$script_dir" == *'`'* || "$script_dir" == *$'\n'* ]]; then
  echo "Unsupported character in cron script path" >&2
  exit 1
fi
cron_file="$(mktemp)"
trap 'rm -f "$cron_file"' EXIT
cat > "$cron_file" <<CRON
# Managed by proxmox/emby/install-cron.sh. Daily at 04:30 host local time.
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
30 4 * * * root "$script_dir/upgrade.sh" >> /var/log/emby-upgrade.log 2>&1
CRON
install -o root -g root -m 0644 "$cron_file" /etc/cron.d/emby-upgrade
cat > "$cron_file" <<'LOGROTATE'
/var/log/emby-upgrade.log {
    weekly
    rotate 8
    compress
    missingok
    notifempty
    create 0640 root root
}
LOGROTATE
install -o root -g root -m 0644 "$cron_file" /etc/logrotate.d/emby-upgrade
echo "Installed daily Emby/Nubile upgrade at 04:30. Log: /var/log/emby-upgrade.log"
