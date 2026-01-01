#!/bin/bash

home_assistant_running_in_vagrant=false
home_assistant_running_in_haos=true

cd /etc/zabbix/zabbix_agent2.d/bash_configs/home-assistant/zabbix
source lib/ha-running-in-vagrant-on-in-proxmox.sh


if [ "$home_assistant_running_in_vagrant" = true ]; then
	ssh root@$ssh_host $ssh_port 'docker exec hassio_cli ha addons' 2>/dev/null > ha-addons.yaml
elif [ "$home_assistant_running_in_haos" = true ]; then
	ssh root@$ssh_host $ssh_port 'ha addons' 2>/dev/null > ha-addons.yaml
else
	sudo ha addons 2>/dev/null > ha-addons.yaml
fi

addons_not_up_to_date='';

# https://stackoverflow.com/a/70841936
while IFS=$'\t' read -r name version version_latest _; do
    #echo "Name:  $name"
    #echo "Version: $version"
    #echo "Version-latest:  $version_latest"
    if [ ! "$version" = "$version_latest" ]; then
        addons_not_up_to_date="$addons_not_up_to_date,$name";
    fi 
# previously it was 'yq eval-all instead yq -r'
done < <(yq -r '.addons[] | [.name, .version, .version_latest] | @tsv' ha-addons.yaml)

echo -n > ha-addons.yaml

if [ "$addons_not_up_to_date" = "" ]; then
    echo true;
else
    echo "false$addons_not_up_to_date";
fi

exit

