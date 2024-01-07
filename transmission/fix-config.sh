#!/bin/bash

service transmission-daemon stop
#su debian-transmission -c "cp /mnt/MargokPool/home/sup/code/nordvpn-torrent/settings.json /mnt/PlexPool/plex/transmission-daemon/settings.json"
cp /mnt/MargokPool/home/sup/code/nordvpn-torrent/settings.json /mnt/PlexPool/plex/transmission-daemon/settings.json
service transmission-daemon start

