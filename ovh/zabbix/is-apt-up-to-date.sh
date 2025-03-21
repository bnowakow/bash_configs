#!/bin/bash

# setting english locale since we're greping a particular string
export LC_ALL=en_US.UTF-8 

# https://askubuntu.com/a/510161
sudo /bin/apt-get update > /dev/null 2> /dev/null
if ! sudo /bin/apt-get --simulate upgrade | grep 'The following packages will be upgraded' > /dev/null && ! sudo /bin/apt-get --simulate upgrade | grep 'The following packages have been kept back' > /dev/null; then
    echo true
else
    echo false,$(sudo /bin/apt-get --simulate upgrade | grep 'The following packages will be upgraded' -A1 | tail -1) $(sudo /bin/apt-get --simulate upgrade | grep 'The following packages have been kept back' -A1 | tail -1)
fi

