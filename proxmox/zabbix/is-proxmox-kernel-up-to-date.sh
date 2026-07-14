#!/bin/bash

local_version=$(uname -r)
current_version=$(ls -1 /boot/vmlinuz-* | sort -V | tail -1 | sed 's#/boot/vmlinuz-##')

if [ "$local_version" = "$current_version" ]; then
    echo true
else
    echo false,$local_version,$current_version
fi


