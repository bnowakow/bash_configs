#!/bin/bash

rm /etc/zabbix/zabbix_agentd.conf.d/zabbix*.conf
find /etc/zabbix/zabbix_agentd.conf.d -name 'zabbix*.conf' | xargs -I{} cp {} /etc/zabbix/zabbix_agentd.conf.d
service zabbix-agent restart

