#!/bin/bash

# to run it with zabbix user run:
# sudo usermod -aG nordvpn zabbix

if nordvpn status | grep Status | grep Connected > /dev/null; then 
	echo true; 
else 
	echo false; 
fi

