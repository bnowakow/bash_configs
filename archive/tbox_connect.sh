#!/bin/bash

#echo "Tunel setup 1"
#ssh -f -L 9091:localhost:9091 kszczep@tbox cat -
echo "sshfs"
sshfs kszczep@tbox:/home/kszczep/torrents /Users/sup/Movies/tbox
echo "done"
echo "Tunel setup 2"
ssh -L 9091:localhost:9091 kszczep@tbox cat -
