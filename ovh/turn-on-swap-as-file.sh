#!/bin/bash

# https://www.digitalocean.com/community/tutorials/how-to-configure-virtual-memory-swap-file-on-a-vps

# TODO check if root
echo "TODO check if root"

cd /var
touch swap.img
chmod 600 swap.img
dd if=/dev/zero of=/var/swap.img bs=1024k count=4000 # 4 GB
mkswap /var/swap.img
swapon /var/swap.img
echo "/var/swap.img none swap sw 0 0"
#sysctl -w vm.swappiness=30 # it was 60 in debian, didn't change
sysctl -a | grep vm.swappiness

