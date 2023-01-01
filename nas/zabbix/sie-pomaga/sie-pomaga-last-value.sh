#!/bin/bash

url="https://www.siepomaga.pl/api/v1/causes/eAtDlJ/stats?locale=pl"

cd /mnt/MargokPool/home/sup/code/bash_configs/nas/zabbix/sie-pomaga;

touch sie-pomaga-value-last.json
rm sie-pomaga-value-current.json 2>/dev/null

curl $url > sie-pomaga-value-current.json 2>/dev/null
#dos2unix sie-pomaga-value-current.json

if ! cmp -s sie-pomaga-value-current.json sie-pomaga-value-last.json; then
    cp sie-pomaga-value-current.json sie-pomaga-value-last.json
    jq -c ".data.datetime += \"$(date +%Y-%m-%d\ %H:%M)\"" sie-pomaga-value-current.json  >> sie-pomaga-values.txt
fi

jq '.data.amount,.data.payments_count' sie-pomaga-value-current.json
rm sie-pomaga-value-current.json

