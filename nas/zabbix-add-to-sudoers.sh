#!/bin/bash

# TODO after fresh install there is no zabbix installed. run provision first and reboot and check if zabbix would be added to sudoers automatically
cd /etc/zabbix/zabbix_agent2.d/homelab/nas || exit 1
if sudo grep -qF 'Cmnd_Alias ZABBIX_CMD=' /etc/sudoers; then
    echo "Zabbix sudoers rules are already present."
else
    sudo tee -a /etc/sudoers < zabbix-sudoers
fi
# TODO add bash for zabbix account, run
# /etc/zabbix/zabbix_agent2.d/homelab/nas/zabbix/is-plex-running/1-install-depencencies.sh
# /etc/zabbix/zabbix_agent2.d/homelab/nas/zabbix/is-plex-running/2-build.sh
# and disable it back
