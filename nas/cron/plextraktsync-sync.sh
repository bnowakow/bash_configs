#!/bin/bash

# https://stackoverflow.com/a/18216122
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

heavyscirpt_location="/mnt/MargokPool/home/sup/code/heavy_script/heavy_script.sh";

# TODO check if below is number and throw error if not
plextraktsync_heavyscript_menu_number=$(echo "0" | sudo $heavyscirpt_location pod --shell | grep plextraktsync | sed 's/).*//')

# https://stackoverflow.com/a/8467449
# below always runs 1st pod, it might cause problems
printf "$plextraktsync_heavyscript_menu_number\n1\n /app/plextraktsync.sh sync" | $heavyscirpt_location pod --shell


