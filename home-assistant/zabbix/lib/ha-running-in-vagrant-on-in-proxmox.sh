#!/bin/bash

if [ "$home_assistant_running_in_vagrant" = true ]; then
	vagrant_ssh_port=$(cd /mnt/MargokPool/home/sup/code/bash_configs/home-assistant; sudo su sup -c "vagrant port --guest 22")
	ssh_port="-p $vagrant_ssh_port"
	ssh_host="localhost"
else
	ssh_port=""
	ssh_host="homeassistant.localdomain"
fi

