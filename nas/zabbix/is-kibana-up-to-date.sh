#!/bin/bash

current_version=$(curl https://www.elastic.co/downloads/elasticsearch 2> /dev/null | grep Version | head -1 | sed 's/.*Version:\ <\/strong>//' | sed 's/<.*//');
# TODO remove \r from end of local_version
local_version=$(sudo /usr/bin/su sup -c 'cd /mnt/MargokPool/home/sup/code/bash_configs/nas/zabbix/sie-pomaga; vagrant ssh -c "docker ps | grep elasticsearch | sed s/.*elasticsearch:// | sed s/\ .*$//" 2>/dev/null');

if [ "$current_version" = "$local_version" ]; then
    echo "true";
else
    echo "false,$local_version,$current_version";
fi

