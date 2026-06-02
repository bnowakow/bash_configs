#!/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$script_dir/sie-pomaga-lib.sh"

per_page=100

sie_pomaga_cd

if [ -f sie-pomaga-list-of-donations.txt ]; then
    mv sie-pomaga-list-of-donations.txt sie-pomaga-list-of-donations.old.txt
fi

after_id=""
after_value=""

while true; do
    url=$(sie_pomaga_payments_url "$per_page" "$after_id" "$after_value")

    wget -q -O sie-pomaga-list-of-donations-in-progress.json "$url"

    number_of_donations=$(jq '.data | length' sie-pomaga-list-of-donations-in-progress.json)
    echo number_of_donations=$number_of_donations

    jq -c '.data[] | {
        name: (.payer.name // ""),
        value: (.amount // ""),
        datetime: (.state_changed_at // ""),
        comment: (.comment_text // ""),
        id: .id
    }' sie-pomaga-list-of-donations-in-progress.json >> sie-pomaga-list-of-donations.txt

    if [ "$number_of_donations" -lt "$per_page" ]; then
        break
    fi

    after_id=$(jq -r '.data[-1].id // ""' sie-pomaga-list-of-donations-in-progress.json)
    after_value=$(jq -r '.data[-1].state_changed_at // ""' sie-pomaga-list-of-donations-in-progress.json)

    if [ -z "$after_id" ] || [ -z "$after_value" ]; then
        break
    fi
done

rm sie-pomaga-list-of-donations-in-progress.json
