#!/bin/bash

cat zabbix-sudoers | sudo tee -a /etc/sudoers
# TODO add bash for zabbix account, run
# /etc/zabbix/zabbix_agent2.d/bash_configs/nas/zabbix/is-plex-running/1-install-depencencies.sh
# /etc/zabbix/zabbix_agent2.d/bash_configs/nas/zabbix/is-plex-running/2-build.sh
# and disable it back

