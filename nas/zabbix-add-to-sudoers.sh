#!/bin/bash

# TODO after fresh install there is no zabbix installed. run provision first and reboot and check if zabbix would be added to sudoers automatically
cd /mnt/MargokPool/home/sup/code/bash_configs/nas
cat zabbix-sudoers | sudo tee -a /etc/sudoers
# TODO add bash for zabbix account, run
# /etc/zabbix/zabbix_agent2.d/bash_configs/nas/zabbix/is-plex-running/1-install-depencencies.sh
# /etc/zabbix/zabbix_agent2.d/bash_configs/nas/zabbix/is-plex-running/2-build.sh
# and disable it back

