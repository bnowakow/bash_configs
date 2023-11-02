#!/bin/bash

loginctl enable-linger sup
mkdir -p /home/sup/.config/systemd/user
cp service-install/ovh-ha-ssh-tunnel.service ~/.config/systemd/user
systemctl --user enable ovh-ha-ssh-tunnel
systemctl --user status ovh-ha-ssh-tunnel

