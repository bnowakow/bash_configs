#!/usr/bin/env bash

export LC_ALL=C.UTF-8
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

if ! /usr/bin/sudo -n /bin/apt-get update >/dev/null; then
    echo 'false,apt update failed'
    exit 0
fi

if ! upgrade_result=$(/usr/bin/sudo -n /bin/apt-get --simulate upgrade); then
    echo 'false,apt upgrade check failed'
    exit 0
fi

upgrades=$(printf '%s\n' "$upgrade_result" | awk '/^Inst / { print $2 }')
kept_back=$(printf '%s\n' "$upgrade_result" | awk '
    /^The following packages have been kept back:/ { capture = 1; next }
    capture && /^[[:space:]]+/ { for (i = 1; i <= NF; i++) print $i; next }
    capture { exit }
')
packages=$(printf '%s\n%s\n' "$upgrades" "$kept_back" | awk 'NF' | sort -u | paste -sd ' ' -)

if [[ -z "$packages" ]]; then
    echo true
else
    echo "false,$packages"
fi
