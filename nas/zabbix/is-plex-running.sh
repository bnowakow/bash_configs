#!/bin/bash

cd /etc/zabbix/zabbix_agent2.d/bash_configs/nas/zabbix
cd is-plex-running
# NotOpenSSLWarning: urllib3 v2.0 only supports OpenSSL 1.1.1+, currently the 'ssl' module is compiled with 'CorSSL v1.1.1t.001'. See: https://github.com/urllib3/urllib3/issues/3020
./3-run.sh 2>/dev/null
cd ../

