#!/bin/bash

#https://gist.github.com/tree-s/1b2177bac1d8f2b70fac9e235a7f262c
host=transmission.localdomain.bnowakowski.pl
port=9091
user=transmission
pass=$(cat .transmission-password)

curl_transmission() {
    sessid=$(curl --silent --anyauth --user $user:$pass "http://$host:$port/transmission/rpc" | sed 's/.*<code>//g;s/<\/code>.*//g')
    #echo sessid=$sessid
    #curl -X GET --anyauth --user $user:$pass --header "$sessid" "http://$host:$port/transmission/web/"

    transmission_http_code=$(curl -s -o /dev/null -w "%{http_code}" -X GET --anyauth --user $user:$pass --header "$sessid" "http://$host:$port/transmission/web/")
    echo $transmission_http_code
}

for try in `seq 1 3`; do
    echo try=$try;
    date;
    transmission_http_code=$(curl_transmission)
    echo transmission_http_code=$transmission_http_code
    if [ $transmission_http_code = "200" ]; then
        echo "transmission is up"
        exit
    fi    
    sleep 5;
done




