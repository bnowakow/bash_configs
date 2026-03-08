#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_template_rel="logrotate-helm-upgrade-apps.conf"
config_template="$script_dir/$config_template_rel"
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

if [ ! -f "$config_template" ]; then
  echo "Template not found: $config_template" >&2
  exit 1
fi

rendered_config="$(mktemp)"
trap 'rm -f "$rendered_config"' EXIT

sed "s|__LOG_GLOB__|$log_glob|g" "$config_template" > "$rendered_config"

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
