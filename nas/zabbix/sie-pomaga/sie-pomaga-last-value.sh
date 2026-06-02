#!/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$script_dir/sie-pomaga-lib.sh"

sie_pomaga_cd

touch sie-pomaga-value-last.json
rm sie-pomaga-value-current.json 2>/dev/null

# for some reason curl no longer downloads json (maybe headers that are set in e.g. sie-pomaga-list-of-donations.sh), for some quick workaround wget is used
#curl "$SIE_POMAGA_PERMALINK_URL" > sie-pomaga-value-current-raw.json 2>/dev/null
sie_pomaga_fetch_statistics_raw sie-pomaga-value-current-raw.json
#dos2unix sie-pomaga-value-current.json

sie_pomaga_normalize_statistics sie-pomaga-value-current-raw.json > sie-pomaga-value-current.json

if ! cmp -s sie-pomaga-value-current.json sie-pomaga-value-last.json; then
    cp sie-pomaga-value-current.json sie-pomaga-value-last.json
    jq -c ".data.datetime += \"$(date +%Y-%m-%d\ %H:%M)\"" sie-pomaga-value-current.json  >> sie-pomaga-values.txt
fi

jq '.data.funds_current,.data.donors_count' sie-pomaga-value-current.json
rm sie-pomaga-value-current.json sie-pomaga-value-current-raw.json
