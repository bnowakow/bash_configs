#!/bin/bash

if [ "$home_assistant_running_in_vagrant" = true ]; then
	vagrant_path="/mnt/MargokPool/home/sup/code/bash_configs/home-assistant";
    vagrant_port_cmd="vagrant port --guest 22"
    if [ "$(whoami)" = "sup" ]; then
        vagrant_ssh_port=$(cd $vagrant_path; $vagrant_port_cmd)
    else
        vagrant_ssh_port=$(cd $vagrant_path; sudo su sup -c "$vagrant_port_cmd")
	fi
    ssh_port="-p $vagrant_ssh_port"
	ssh_host="localhost"
else
	ssh_port=""
	ssh_host="home-assistant.localdomain.bnowakowski.pl"
fi

