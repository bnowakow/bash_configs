#!/bin/bash

# TODO do an array and loop over it
mkdir -p /tmp/sshfs/archive
mkdir -p /tmp/sshfs/plex
sshfs sup@nas.localdomain.bnowakowski.pl:/mnt/MargokPool/archive /tmp/sshfs/archive
sshfs sup@nas.localdomain.bnowakowski.pl:/mnt/PlexPool/plex /tmp/sshfs/plex

