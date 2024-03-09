#!/bin/bash

sum=0

jq '.' sie-pomaga-old-amounts.txt | grep -v '{' | grep -v '}' | grep -v ': 0,' | while read line; do
    date=$(echo $line | sed 's/:.*//' | sed 's/"//g')
    daily_amount=$(echo $line | sed 's/.*: //' | sed 's/,//' | sed 's/"//g')
    sum=$(echo $sum + $daily_amount | bc)

    #echo $date $sum;
    echo "{\"data\":{\"amount\":\"$sum\",\"datetime\":\"$date 00:00\"}}"
    # {"data":{"payments_count":351,"amount":"47363.84","percentage":"0","amount_left":"0","target":null,"datetime":"2023-01-01 21:13"}}
done

