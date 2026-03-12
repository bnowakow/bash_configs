#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log_glob="$script_dir/logs/helm-upgrade-*.log"
target_config="/etc/logrotate.d/helm-upgrade-apps"

action="install"
if [ "${1:-}" = "--print" ]; then
  action="print"
elif [ "${1:-}" = "--help" ]; then
  cat <<USAGE
Usage: $(basename "$0") [--print|--help]

Options:
  --print   Print rendered config to stdout, do not install.
  --help    Show this help.
USAGE
  exit 0
elif [ -n "${1:-}" ]; then
  echo "Unknown argument: $1" >&2
  exit 2
fi

rendered_config="$(mktemp)"
trap 'rm -f "$rendered_config"' EXIT

cat > "$rendered_config" <<EOF
# Debian logrotate config for helm-upgrade-apps logs

$log_glob {
    daily
    rotate 30
    maxage 90
    missingok
    notifempty
    compress
    delaycompress
}
EOF

if [ "$action" = "print" ]; then
  cat "$rendered_config"
  exit 0
fi

echo "Installing logrotate config to $target_config"
sudo install -m 0644 "$rendered_config" "$target_config"

echo "Installed. Validate with:"
echo "  sudo logrotate -d $target_config"
echo "Force one run with:"
echo "  sudo logrotate -f $target_config"
