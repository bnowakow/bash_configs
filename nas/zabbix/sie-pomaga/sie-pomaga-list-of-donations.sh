#!/bin/bash

next_page_url="/raczka-kuby?last_payment_id=&last_payment_time=&tabs=";
stop_page_url='":null}}'

rm sie-pomaga-list-of-donations.txt

while true; do

    curl \                                                                                                                                                                                     -H "Host: www.siepomaga.pl" \                                                                                                                                                          -H "accept: application/json" \                                                                                                                                                        --compressed \
        "https://www.siepomaga.pl$next_page_url" \
        > sie-pomaga-list-of-donations-in-progress-1.json 2>/dev/null

    cat sie-pomaga-list-of-donations-in-progress-1.json | tr '<' '\n<' > sie-pomaga-list-of-donations-in-progress-2.json

    number_of_donations=$(grep donation-card-component__name sie-pomaga-list-of-donations-in-progress-2.json | wc -l)
    number_of_values=5

    # name
    grep donation-card-component__name sie-pomaga-list-of-donations-in-progress-2.json | sed "s/.*>\\\n//" | sed "s/\ \ //g" | sed "s/\\\n$//" \
        > sie-pomaga-list-of-donations-in-progress-3.json
    # donation value
    grep data-common-formatted-number-component-raw-value-value sie-pomaga-list-of-donations-in-progress-2.json | sed "s/.*>\\\n//" | sed "s/\ \ //g" | sed "s/\\\n$//" \
        >> sie-pomaga-list-of-donations-in-progress-3.json
    # datetime
    grep datetime sie-pomaga-list-of-donations-in-progress-2.json | sed "s/time datetime=\\\.//" | sed "s/\\\.*//" \
        >> sie-pomaga-list-of-donations-in-progress-3.json
    # comment
    grep donation-card-component__text__comment sie-pomaga-list-of-donations-in-progress-2.json | sed "s/.*>\\\n//" | sed "s/\ \ //g" | sed "s/\\\n$//" \
        >> sie-pomaga-list-of-donations-in-progress-3.json
    # id
    grep donation-card-comment sie-pomaga-list-of-donations-in-progress-2.json | sed "s/.*donation-card-comment-//" | sed "s/\\\.*//" \
        >> sie-pomaga-list-of-donations-in-progress-3.json

    values_names=("name" "value" "datetime" "comment" "id")

    for (( j=0; j<$number_of_donations; j++ ))
    do
        jq -n '{}' > sie-pomaga-list-of-donations-in-progress-4.json
        for (( i=0; i<$number_of_values; i++ ))
        do
            k=$(($i*$number_of_donations+$j+1))
            value_name=${values_names[$i]}
            value=$(sed -n "$k""p" < sie-pomaga-list-of-donations-in-progress-3.json)
            jq -c  ".$value_name += \"$value\"" sie-pomaga-list-of-donations-in-progress-4.json > sie-pomaga-list-of-donations-in-progress-5.json
        cp sie-pomaga-list-of-donations-in-progress-5.json sie-pomaga-list-of-donations-in-progress-4.json
        done
        jq -c . sie-pomaga-list-of-donations-in-progress-4.json >> sie-pomaga-list-of-donations.txt
    done

    next_page_url=$(grep load_more_button sie-pomaga-list-of-donations-in-progress-1.json | sed "s/.*load_more_button//" | sed "s/.*data-url=\\\.//" | sed "s/..\\\n.*//")
    echo next_page_url=$next_page_url

    rm sie-pomaga-list-of-donations-in-progress-*

    if [ "$next_page_url" = "$stop_page_url" ]; then
        break;
    fi
done


