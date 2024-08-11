#!/bin/bash

local_version=$(uname -r)
current_version=$(ls -tr1 /boot/vmlinuz-* | tail -1 | sed 's#/boot/vmlinuz-##')

if [ "$local_version" = "$current_version" ]; then
    echo true
else
    echo false,$local_version,$current_version
fi


