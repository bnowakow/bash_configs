#!/bin/bash

# https://unix.stackexchange.com/a/486175
sudo grep -B100 -A3 "BIOS-provided physical RAM map" --group-separator=$'\n\n' /var/log/syslog |  less

