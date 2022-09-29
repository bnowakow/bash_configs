#!/bin/bash

current_version=$(curl https://www.truenas.com/download-truenas-scale/ 2> /dev/null | grep iso | head -1 | sed 's/\.iso.*//' | sed 's/.*SCALE\-//g')
local_version=$(cat /etc/version)

#echo "local_version=$local_version current_version=$current_version";

if [ "$current_version" = "$local_version" ]; then
    echo true;
else
    echo false,$local_version,$current_version;
fi

