#!/bin/bash

rm /etc/zabbix/zabbix_agent2.d/zabbix*.conf
find -L /etc/zabbix/zabbix_agent2.d -name 'zabbix*.conf' | grep -v zabbix_agent2.conf | xargs -I{} cp {} /etc/zabbix/zabbix_agent2.d/
service zabbix-agent2 restart

