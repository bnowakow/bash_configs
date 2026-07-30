#!/bin/bash

set -o pipefail
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

newest_docker_image() {
    local image_name="${1:-zabbix/zabbix-web-nginx-pgsql}"
    local max_pages=3
    local url="https://hub.docker.com/v2/repositories/${image_name}/tags?page_size=100"
    local page=1
    local data
    local tags=''

    while [ -n "$url" ] && [ "$page" -le "$max_pages" ]; do
        data=$(curl -fsSL "$url") || return 1

        tags+=$(echo "$data" | jq -r '
            .results[].name
            | select(contains("ubuntu"))
            | select(test("[0-9]+\\.[0-9]+"))
            | select(startswith("sha256-") | not)
            | select(endswith(".sig") | not)
        ')
        tags+=$'\n'

        url=$(echo "$data" | jq -r '.next // empty') || return 1
        page=$((page + 1))
    done

    printf '%s' "$tags" | sort -V | tail -n 1
}

current_zabbix_image_tag() {
    helm get values zabbix \
        --namespace apps-zabbix \
        --kubeconfig "$KUBECONFIG" \
        --output yaml |
        awk '$1 == "zabbixImageTag:" { gsub(/^"|"$/, "", $2); print $2; exit }'
}

newest_image_tag="$(newest_docker_image "$@")" || {
    echo "false,error-fetching-docker-tags"
    exit 3
}
current_image_tag="$(current_zabbix_image_tag)" || {
    echo "false,error-fetching-zabbix-values"
    exit 3
}

if [ -z "$newest_image_tag" ] || [ -z "$current_image_tag" ]; then
    echo "false,missing-zabbix-image-tag"
    exit 3
fi

if [ "$current_image_tag" = "$newest_image_tag" ]; then
    echo true
else
    echo "false,$current_image_tag,$newest_image_tag"
    exit 1
fi
