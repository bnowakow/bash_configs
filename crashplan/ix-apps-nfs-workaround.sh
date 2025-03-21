#!/bin/bash

# TODO copied from /mnt/MargokPool/home/sup/code/nordvpn-torrent/restart-vagrant.sh @nfs-workaround_manual-nfs branch
#grep Plex /etc/exports | grep insecure || {
#    echo '#nord-virtualbox' | sudo tee -a /etc/exports
#    echo '"/mnt/MargokPool/archive"       127.0.0.1(rw,no_subtree_check,insecure,sync,no_root_squash,anonuid=114,anongid=119,fsid=365136518)' | sudo tee -a /etc/exports
#    echo '"/mnt/PlexPool/plex"            127.0.0.1(rw,no_subtree_check,insecure,sync,no_root_squash,anonuid=114,anongid=119,fsid=365136519)' | sudo tee -a /etc/exports
#    echo '"/mnt/MargokPool/home/sup"      127.0.0.1(rw,no_subtree_check,insecure,sync,no_root_squash,anonuid=114,anongid=119,fsid=365136517)' | sudo tee -a /etc/exports
#}
#sudo service nfs-kernel-server start
#sudo exportfs -r; sudo exportfs

# on nas
# grep ix-apps /etc/exports                                                            
# "/mnt/.ix-apps/app_mounts/minio/export" 192.168.0.0/16(ro,no_root_squash,no_subtree_check)

# on crashplan
# sudo groupadd -g 473 ix-apps
# sudo usermod -a -G 473 root
# sudo usermod -a -G 473 sup
# grep ix-apps /etc/fstab
# nas.localdomain.bnowakowski.pl:/mnt/.ix-apps/app_mounts/minio/export       /mnt/ix-apps/app_mounts/minio/export    nfs     ro,hard,timeo=14,rsize=8192,wsize=8192,intr     0       0
# sudo systemctl daemon-reload

