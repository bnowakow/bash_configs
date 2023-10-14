#!/bin/bash

# https://stackoverflow.com/a/18216122
if [ "$EUID" -ne 0 ]; then 
	echo "Please run as root"
	exit
fi

cd /home/sup/code/bash_configs/transmission/

./nord-run.sh
mount -vvv /mnt/PlexPool/plex
mount -vvv /mnt/MargokPool/home
./fix-config.sh
./transmission-daemon-keepalive.sh # TODO later in background

