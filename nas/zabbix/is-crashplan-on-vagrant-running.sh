#!/bin/bash

sudo /usr/bin/su sup -c 'cd /mnt/MargokPool/home/sup/code/crashplan-docker; vagrant ssh -c "if docker exec crashplan /usr/local/crashplan/bin/service.sh status | grep running > /dev/null; then echo true; else echo false; fi" 2>/dev/null'
