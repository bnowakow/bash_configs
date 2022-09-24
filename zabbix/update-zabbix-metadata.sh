#!/bin/bash

rm /etc/zabbix/zabbix_agent2.d/zabbix*.conf
find /etc/zabbix/zabbix_agent2.d -name 'zabbix*.conf' | xargs -I{} cp {} /etc/zabbix/zabbix_agent2.d/
service zabbix-agent2 restart

