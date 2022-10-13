#!/bin/bash

# https://askubuntu.com/a/510161
sudo /bin/apt-get update > /dev/null 2> /dev/null
if sudo /bin/apt-get --simulate upgrade | grep "0 upgraded" > /dev/null; then
    echo true
else
    echo false,$(sudo /bin/apt-get --simulate upgrade | grep 'The following packages will be upgraded' -A1 | tail -1)
fi

