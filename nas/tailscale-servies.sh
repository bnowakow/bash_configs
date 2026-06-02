#!/bin/bash

# DOESN'T WORK YET: on margok-nas, inside docker app:
tailscale serve --service=svc:jellyfin --https=443 127.0.0.1:30013

# proxmox3
sudo tailscale serve --service=svc:jellyseerr --https=443 https://jellyseerr.rancher.localdomain.bnowakowski.pl:443


