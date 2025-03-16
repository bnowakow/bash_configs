#!/bin/bash

app_name="${1:-tailscale}"

if sudo /bin/cli -c "app outdated_docker_images $app_name" | grep "empty list" > /dev/null; then
    echo true;
else
    echo false,$(sudo /bin/cli -c "app outdated_docker_images $app_name");
fi

