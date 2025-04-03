#!/bin/bash

app_name="${1:-tailscale}"

if sudo /bin/cli -c "app upgrade_summary $app_name" 2>&1 | grep "Error: No upgrade available for" > /dev/null; then
    echo true;
else
    echo false,$(sudo /bin/cli -c "app upgrade_summary $app_name" 2>&1 | grep latest_version | awk '{print $4}');
fi

