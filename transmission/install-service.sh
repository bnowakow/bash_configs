#!/bin/bash -x

# https://stackoverflow.com/a/18216122
if [ "$EUID" -ne 0 ]; then
	echo "Please run as root"
	exit
fi

cp service-install/nordvpn-and-transmission.service /etc/systemd/system/
systemctl enable nordvpn-and-transmission
systemctl status nordvpn-and-transmission

