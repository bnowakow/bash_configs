#!/bin/bash

# TODO make sure running as root

service transmission-daemon stop
# cp /mnt/MargokPool/home/sup/code/nordvpn-torrent/settings.json /mnt/PlexPool/plex/transmission-daemon/settings.json
cp /mnt/MargokPool/home/sup/code/bash_configs/transmission/settings.json /mnt/PlexPool/plex/transmission-daemon/settings.json
chown debian-transmission:debian-transmission /mnt/PlexPool/plex/transmission-daemon/settings.json
service transmission-daemon start
service transmission-daemon status

