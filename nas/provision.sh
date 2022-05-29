#!/bin/bash

sudo chmod +x /bin/apt /bin/apt-key /bin/apt-get /bin/apt-cache /bin/apt-config

sudo apt update
sudo apt install -y screen vim vagrant wget gnupg2 hddtemp ncdu elinks jdupes hfsprogs libicu-dev bzip2 cmake libz-dev libbz2-dev fuse3 libfuse3-3 libfuse3-dev clang git libattr1-dev libfsapfs-utils


wget -q https://www.virtualbox.org/download/oracle_vbox_2016.asc -O- | sudo apt-key add -
sudo echo "deb [arch=amd64] http://download.virtualbox.org/virtualbox/debian bullseye contrib" | sudo tee /etc/apt/sources.list.d/virtualbox.list
sudo apt update
sudo apt-cache madison linux-headers-truenas-amd64
#sudo apt install -y linux-headers-truenas-amd64=5.10.70+truenas-1
sudo apt install -y linux-headers-truenas-amd64
sudo apt install -y virtualbox-6.1 dkms

sudo apt-get install software-properties-common dirmngr apt-transport-https -y 
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C4A05888A1C4FA02E1566F859F2A29A569653940 
sudo add-apt-repository "deb http://kryptco.github.io/deb kryptco main" # non-Kali Linux only 
sudo apt-get update 
sudo apt-get install kr -y 

# https://computingforgeeks.com/how-to-install-latest-docker-compose-on-linux/
curl -s https://api.github.com/repos/docker/compose/releases/latest | grep browser_download_url  | grep docker-compose-linux-x86_64 | cut -d '"' -f 4 | wget -qi -
chmod +x docker-compose-linux-x86_64
sudo mv docker-compose-linux-x86_64 /usr/local/bin/docker-compose

chsh -s $(which zsh)

if ! crontab -l | grep ovh_backup_download; then
    { crontab -l; echo '02 05 * * * /mnt/MargokPool/home/sup/code/bash_configs/proxmox_backup_download.sh'; } | crontab -
    { crontab -l; echo '02 15 * * * /mnt/MargokPool/home/sup/code/bash_configs/ovh_backup_download.sh'; } | crontab -
fi

