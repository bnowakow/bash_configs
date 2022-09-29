#!/bin/bash

sudo /usr/bin/su sup -c 'cd /mnt/MargokPool/home/sup/code/nordvpn-torrent; vagrant ssh -c "if service transmission-daemon status | grep Active | grep running> /dev/null; then echo true; else echo false; fi" 2>/dev/null'
