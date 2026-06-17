#!/usr/bin/env bash

set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cron_script="$script_dir/delete-stuck-expired-cert-requests.sh"
log_file="/var/log/delete-stuck-expired-cert-requests.log"
logrotate_source="$script_dir/logrotate-delete-stuck-expired-cert-requests.conf"
logrotate_target="/etc/logrotate.d/delete-stuck-expired-cert-requests"
cron_line="*/15 * * * * PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin KUBECONFIG=/etc/rancher/k3s/k3s.yaml $cron_script --delete --stuck-after-minutes 180 >> $log_file 2>&1"

if [[ ! -x "$cron_script" ]]; then
  echo "ERROR: cron script is not executable: $cron_script" >&2
  exit 1
fi

if [[ ! -f "$logrotate_source" ]]; then
  echo "ERROR: logrotate config not found: $logrotate_source" >&2
  exit 1
fi

current_crontab="$(mktemp)"
new_crontab="$(mktemp)"
trap 'rm -f "$current_crontab" "$new_crontab"' EXIT

sudo crontab -l -u root > "$current_crontab" 2>/dev/null || true

if grep -Fq "$cron_script --delete --stuck-after-minutes 180" "$current_crontab"; then
  echo "Root crontab already contains delete-stuck-expired-cert-requests cron command."
else
  cp "$current_crontab" "$new_crontab"
  if [[ -s "$new_crontab" ]] && [[ "$(tail -c 1 "$new_crontab")" != "" ]]; then
    echo >> "$new_crontab"
  fi
  echo "$cron_line" >> "$new_crontab"
  sudo crontab -u root "$new_crontab"
  echo "Installed root crontab entry:"
  echo "  $cron_line"
fi

sudo install -m 0644 "$logrotate_source" "$logrotate_target"
sudo logrotate -d "$logrotate_target" >/dev/null

echo "Installed logrotate config: $logrotate_target"
echo "Cron log: $log_file"
