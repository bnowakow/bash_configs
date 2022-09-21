#!/bin/bash

sudo /bin/apt-get update > /dev/null
if sudo /bin/apt-get --simulate upgrade | grep "0 upgraded" > /dev/null; then
    echo true
else
    echo false
fi

