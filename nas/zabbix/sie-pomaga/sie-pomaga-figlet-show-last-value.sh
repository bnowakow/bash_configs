#!/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$script_dir/sie-pomaga-lib.sh"

font="Doh.flf"

sie_pomaga_cd

while true; do

    amount=$(jq .data.funds_current sie-pomaga-value-last.json)
    donors_count=$(jq .data.donors_count sie-pomaga-value-last.json)

    # fonts are from https://github.com/xero/figlet-fonts

    clear;
    date -r sie-pomaga-value-last.json | /usr/bin/figlet-figlet -w1000 -f "Nancyj.flf";
    # https://unix.stackexchange.com/a/113798
    echo $amount PLN | sed ':a;s/\B[0-9]\{3\}\>/\ \ &/;ta' | /usr/bin/figlet-figlet -w1000 -f $font
    echo $donors_count osob | sed ':a;s/\B[0-9]\{3\}\>/\ \ &/;ta' | /usr/bin/figlet-figlet -w1000 -f $font
    sleep 30;
done
