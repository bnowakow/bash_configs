#!/bin/bash

amount=$(jq .data.amount sie-pomaga-value-last.json)
payments_count=$(jq .data.payments_count sie-pomaga-value-last.json)

# fonts are from https://github.com/xero/figlet-fonts
font="Doh.flf"

while true; do
    clear;
    date -r sie-pomaga-value-last.json | /usr/bin/figlet-figlet -w1000 -f "Nancyj.flf";
    # https://unix.stackexchange.com/a/113798
    echo $amount PLN | sed ':a;s/\B[0-9]\{3\}\>/\ \ &/;ta' | /usr/bin/figlet-figlet -w1000 -f $font
    echo $payments_count osob | sed ':a;s/\B[0-9]\{3\}\>/\ \ &/;ta' | /usr/bin/figlet-figlet -w1000 -f $font
    sleep 60;
done

