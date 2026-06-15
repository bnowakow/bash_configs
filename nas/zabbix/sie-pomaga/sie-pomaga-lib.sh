#!/bin/bash

SIE_POMAGA_DIR="/mnt/MargokPool/home/sup/code/bash_configs/nas/zabbix/sie-pomaga"
SIE_POMAGA_SLUG="raczka-kuby"
SIE_POMAGA_CAUSE_ID="eAtDlJ"
SIE_POMAGA_TARGET_TYPE="Cause"
SIE_POMAGA_LOCALE="pl"

SIE_POMAGA_PERMALINK_URL="https://www.siepomaga.pl/api/donor/web/v2/permalinks/$SIE_POMAGA_SLUG"
SIE_POMAGA_PAYMENTS_BASE_URL="https://www.siepomaga.pl/api/v1/payments"

sie_pomaga_cd() {
    cd "$SIE_POMAGA_DIR" || exit 1
}

sie_pomaga_fetch_statistics_raw() {
    wget -q -O "$1" "$SIE_POMAGA_PERMALINK_URL"
}

sie_pomaga_normalize_statistics() {
    jq -c '{
        data: {
            donors_count: .data.target.needy.cause.donors_count,
            funds_aim: .data.target.needy.cause.funds_aim,
            funds_current: .data.target.needy.cause.funds_current
        }
    }' "$1"
}

sie_pomaga_payments_url() {
    local per_page="$1"
    local after_id="$2"
    local after_value="$3"
    local url

    url="$SIE_POMAGA_PAYMENTS_BASE_URL?per_page=$per_page&target_type=$SIE_POMAGA_TARGET_TYPE&target_id=$SIE_POMAGA_CAUSE_ID&sort_by=newest&locale=$SIE_POMAGA_LOCALE"

    if [ -n "$after_id" ] && [ -n "$after_value" ]; then
        after_value_encoded=$(jq -nr --arg value "$after_value" '$value|@uri')
        url="$url&after_id=$after_id&after_value=$after_value_encoded"
    fi

    echo "$url"
}
