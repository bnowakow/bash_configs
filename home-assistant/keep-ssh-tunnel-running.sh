#!/bin/bash

cd ~/code/bash_configs/home-assistant

while true; do
	curl "https://ovh.bnowakowski.pl:8123" &>/dev/null;
	if [ $? -ne 0 ]; then
		./create-ssh-tunnel.sh
	fi
	sleep 60;
done

