#!/bin/bash

# -H "Authorization: Bearer " \

token=$(cat .home-assistant-token)
json=$(curl -X GET \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
     http://margok.local:8123/api/config 2>/dev/null)
ha_version=$(echo $json | jq '.version')
echo ha_version=$ha_version


