#!/bin/bash

cd /mnt/MargokPool/home/sup/code/vagrant-basebox

# TODO below is copy paste of create-basebox.sh, tried to extract it to separate file and source it but doesn't work with sudo su sup (which is needed for first and third command)
sudo su sup -c "VAGRANT_VAGRANTFILE=Vagrantfile.basebox vagrant box update" > /dev/null
basebox_of_basebox=$(grep -o '^[^#]*' Vagrantfile.basebox | grep 'config.vm.box' | sed 's/^[^"]*"//' | sed 's/\".*//')

latest_ubuntu_version=$(sudo su sup -c "vagrant box list | grep $basebox_of_basebox | tail -1 | sed 's/.*,\ //' | sed 's/)$//'")
# \TODO

sudo su sup -c "vagrant box list | grep 'bnowakow/nordvpn-torrent' | grep $latest_ubuntu_version" > /dev/null

if [ $? -gt 0 ]; then
    echo "false,$latest_ubuntu_version"
else
    echo "true"
fi

