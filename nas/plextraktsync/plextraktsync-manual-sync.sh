#!/bin/bash -x

# https://stackoverflow.com/a/18216122
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

cd /mnt/MargokPool/home/sup/code/heavy_script

menu_item_number=$(echo "0" | sudo ./heavy_script.sh pod --shell | grep plextraktsync | sed 's/).*//');
echo -e "$menu_item_number\n1\n /app/plextraktsync.sh sync" | ./heavy_script.sh pod --shell

