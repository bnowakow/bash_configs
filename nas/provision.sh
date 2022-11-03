#!/bin/bash

sudo chmod +x /bin/apt /bin/apt-key /bin/apt-get /bin/apt-cache /bin/apt-config

curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
sudo add-apt-repository "deb https://download.docker.com/linux/debian/ $(lsb_release -s -c) stable"

sudo apt update
sudo apt install -y screen vim vagrant wget gnupg2 hddtemp ncdu elinks jdupes hfsprogs libicu-dev bzip2 cmake libz-dev libbz2-dev fuse3 libfuse3-3 libfuse3-dev clang git libattr1-dev libfsapfs-utils libicu-dev bzip2 cmake libz-dev libbz2-dev fuse3 libfuse3-3 libfuse3-dev clang git libattr1-dev virtualenv python3-venv docker-compose-plugin

wget -q https://www.virtualbox.org/download/oracle_vbox_2016.asc -O- | sudo apt-key add -
sudo echo "deb [arch=amd64] http://download.virtualbox.org/virtualbox/debian bullseye contrib" | sudo tee /etc/apt/sources.list.d/virtualbox.list
sudo apt update
sudo apt-cache madison linux-headers-truenas-amd64
#sudo apt install -y linux-headers-truenas-amd64=5.10.70+truenas-1
sudo apt install -y linux-headers-truenas-amd64
sudo apt install -y virtualbox-6.1 dkms

# https://computingforgeeks.com/how-to-install-latest-docker-compose-on-linux/
curl -s https://api.github.com/repos/docker/compose/releases/latest | grep browser_download_url  | grep docker-compose-linux-x86_64 | cut -d '"' -f 4 | wget -qi -
chmod +x docker-compose-linux-x86_64
sudo mv docker-compose-linux-x86_64 /usr/local/bin/docker-compose

chsh -s $(which zsh)

# https://linuxnewbieguide.org/how-to-mount-macos-apfs-disk-volumes-in-linux/
sudo cp /mnt/MargokPool/home/sup/code/apfs-fuse/build/apfs-* /usr/local/bin

if ! crontab -l | grep ovh_backup_download; then
    { crontab -l; echo '01 01 * * * /mnt/MargokPool/home/sup/code/bash_configs/nas/cron/proxmox_backup_download.sh'; } | crontab -
    { crontab -l; echo '10 01 * * * /mnt/MargokPool/home/sup/code/bash_configs/nas/cron/home-assistant_backup_download.sh'; } | crontab -
    { crontab -l; echo '01 06 * * * /mnt/MargokPool/home/sup/code/bash_configs/nas/cron/ovh_backup_download.sh'; } | crontab -
    { crontab -l; echo '01 13 * * * /mnt/MargokPool/home/sup/code/zabbix-scripts/3-run.sh'; } | crontab -
fi

# user interactive - generate and copy ssh keys
if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen
fi
ssh-copy-id root@192.168.1.56

sudo apt-get install software-properties-common dirmngr apt-transport-https -y
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C4A05888A1C4FA02E1566F859F2A29A569653940
sudo add-apt-repository "deb http://kryptco.github.io/deb kryptco main" # non-Kali Linux only
sudo apt-get update
sudo apt-get install kr -y

ssh-copy-id -i /mnt/MargokPool/home/sup/.ssh/id_rsa.pub -f sup@ovh.bnowakowski.pl
cp ssh-config /mnt/MargokPool/home/sup/.ssh/config

sudo apt install software-properties-common -y
sudo add-apt-repository 'deb [arch=amd64] https://repo.zabbix.com/zabbix/6.2/debian/ bullseye main contrib non-free'
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 082AB56BA14FE591
sudo apt update
sudo apt install zabbix-agent2
sudo cp /mnt/MargokPool/home/sup/code/bash_configs/zabbix/zabbix_agent2.conf /etc/zabbix
cd /etc/zabbix/zabbix_agent2.d
sudo ln -sf /mnt/MargokPool/home/sup/code/bash_configs bash_configs
cd bash_configs
sudo chown sup:sup -R .
mkdir tmp-zabbix
sudo chown zabbix:zabbix tmp-zabbix
cd ../
sudo usermod -a -G docker zabbix
sudo mkdir -p /var/lib/zabbix/
sudo chown zabbix:zabbix /var/lib/zabbix
sudo ./bash_configs/zabbix/update-zabbix-metadata.sh
sudo ./bash_configs/nas/zabbix-add-to-sudoers.sh

sudo apt-get install unison -y

## https://www.zigbee2mqtt.io/advanced/remote-adapter/connect_to_a_remote_adapter.html
## https://sourceforge.net/p/ser2net/discussion/90083/thread/df1050a576/
## https://forums.raspberrypi.com/viewtopic.php?t=40216
#sudo apt-get install ser2net -y
## TODO check if config already exists
#coordinator_port=$(sudo dmesg | grep 'ch341-uart converter now attached to' | tail -1 | sed 's/.*tty/tty/')
#cp ser2net.config.template ser2net.config
#sed -i "s/PORT/$coordinator_port/" ser2net.config
#cat ser2net.config | sudo tee -a /etc/ser2net.yaml
#rm ser2net.config
#sudo service ser2net restart

sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys CC86BB64
sudo add-apt-repository ppa:rmescandon/yq -y
sudo sed -i -e 's|lunar|focal|g' /etc/apt/sources.list.d/rmescandon-ubuntu-yq-lunar.list
sudo apt-get update #--allow-insecure-repositories
sudo apt-get install yq -y 

sudo apt-get install default-jdk
curl -s https://get.sdkman.io | bash
sdk install kotlin




