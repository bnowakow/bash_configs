#!/bin/bash

local_version=$(dpkg -s homeassistant-supervised | grep '^Version' | sed 's/.*\ //')
current_version=$(curl 'https://api.github.com/repos/home-assistant/supervised-installer/releases/latest' 2>/dev/null | jq .tag_name | sed 's/"//g')

#echo "local_version=$local_version current_version=$current_version";

if [ "$current_version" = "$local_version" ]; then
    echo true;
else
    echo false,$local_version,$current_version;
fi

