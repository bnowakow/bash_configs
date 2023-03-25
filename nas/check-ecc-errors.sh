#!/bin/bash

# TODO check memcheck as well

# pudget ecc check https://www.pugetsystems.com/labs/articles/How-to-Check-ECC-RAM-Functionality-462/#UbuntuLiveCD-ecc_check_c
# works only on some Intel i3
#pudget_file="ecc_check.c"
#if [ ! -f "$pudget_file" ]; then
#    wget "https://pastebin.com/raw/URExZi29" -O $pudget_file
#    gcc $pudget_file -o check-ecc_check-pudget
#fi
#sudo ./check-ecc_check-pudget
#echo

# https://superuser.com/a/893963
sudo inxi -m -xxx
echo

# https://serverfault.com/a/1067167
echo "Below should return ecc and errordetection=multi-bit-ecc"
sudo lshw -class memory|grep ecc
echo

# https://dannyda.com/2022/08/13/how-to-check-if-ecc-ram-is-recognised-enabled-in-the-system-windows-windows-server-linux-debian-ubuntu-kali-linux-redhat-fedora-rocky-linux-etc/
# in above url there's also description for files in /sys/devices/system/edac/mc/mc0
echo "Below should return Multi-bit ECC"
sudo dmidecode --type memory | grep "Error Correction Type"

echo "Total should be bigger than Data"
sudo dmidecode --type memory | grep Width
echo

# https://www.setphaserstostun.org/posts/monitoring-ecc-memory-on-linux-with-rasdaemon/
sudo ras-mc-ctl --error-count
echo

#edac-util --status
# per dimm status
echo "if below returns error go with full edac-util -v"
edac-util -v | grep "edac-util"
# edac-util -v
echo

# scrub kernel bug :/ https://unix.stackexchange.com/a/594729
# to check memory controler name # TODO use this in below commands instead mc0
ls /sys/devices/system/edac/mc/
sudo su -c "echo 1000000 >/sys/devices/system/edac/mc/mc0/sdram_scrub_rate; echo $?"
echo "if below is 0 that's kernel bug https://unix.stackexchange.com/a/59472"
cat /sys/devices/system/edac/mc/mc0/sdram_scrub_rate

