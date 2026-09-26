#!/bin/bash

# https://stackoverflow.com/a/18216122
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

cd /etc/zabbix/zabbix_agent2.d/bash_configs/zabbix

install -m 0644 zabbix_agent2.conf /etc/zabbix/zabbix_agent2.conf
rm /etc/zabbix/zabbix_agent2.d/zabbix*.conf
find -L /etc/zabbix/zabbix_agent2.d -name 'zabbix*.conf' | grep -v zabbix_agent2.conf | xargs -I{} install -m 0644 {} /etc/zabbix/zabbix_agent2.d/
service zabbix-agent2 restart
service zabbix-agent2 status

# TODO wait 5? seconds check status, if failed show
# journalctl -u zabbix-agent2
