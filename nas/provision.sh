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
sudo cp /mnt/MargokPool/home/sup/code/zabbix-docker/zabbix_agent2.conf /etc/zabbix
cd /mnt/MargokPool/home/sup/code/bash_configs
git pull
cd /etc/zabbix/zabbix_agent2.d
sudo cp -r /mnt/MargokPool/home/sup/code/bash_configs .
cd bash_configs
sudo chown sup:sup -R .
mkdir tmp-zabbix
sudo chown zabbix:zabbix tmp-zabbix
cd ../
sudo usermod -a -G docker zabbix
sudo mkdir -p /var/lib/zabbix/
sudo chown zabbix:zabbix /var/lib/zabbix
sudo ./bash_configs/zabbix/update-zabbix-metadata.sh
# TODO add sudoers for zabbix
cat zabbix-sudoers | sudo tee -a /etc/sudoers
# TODO add bash for zabbix account, run 
# /etc/zabbix/zabbix_agent2.d/bash_configs/nas/zabbix/is-plex-running/1-install-depencencies.sh
# /etc/zabbix/zabbix_agent2.d/bash_configs/nas/zabbix/is-plex-running/2-build.sh
# and disable it back

sudo apt-get install unison -y
