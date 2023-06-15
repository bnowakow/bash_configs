#!/bin/bash

current_version=$(curl https://www.elastic.co/downloads/elasticsearch 2> /dev/null | grep Version | head -1 | sed 's/.*Version:\ <\/strong>//' | sed 's/<.*//');
# TODO remove \r from end of local_version
local_version=$(docker ps | grep elasticsearch | sed s/.*elasticsearch:// | sed s/\ .*$//);

if [ "$current_version" = "$local_version" ]; then
    echo "true";
else
    echo "false,$local_version,$current_version";
fi

