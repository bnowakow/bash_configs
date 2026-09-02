#!/bin/bash -x

# TODO check two key add that require's user's input

apt_install() {
    local apt_log
    apt_log=$(mktemp)

    # Keep apt's output visible while retaining it so that configure-only
    # failures can be handled separately from packages that could not be
    # installed at all.
    set -o pipefail
    if sudo apt-get install "$@" 2>&1 | tee "$apt_log"; then
        rm -f "$apt_log"
        return 0
    fi

    # A package may have been unpacked successfully but fail in its
    # post-install/configuration script (for example because TrueNAS keeps
    # /boot read-only).  Do not make those failures abort provisioning.
    if awk '/^dpkg: error processing package / {
            count++
            if ($0 !~ /\(--configure\)/) other_error=1
        }
        END { exit !(count > 0 && !other_error) }' "$apt_log"; then
        while read -r package; do
            [[ -n "$package" ]] && APT_CONFIG_WARNINGS+=("$package")
        done < <(awk '/^dpkg: error processing package .* \(--configure\):/ { print $5 }' "$apt_log")
        rm -f "$apt_log"
        return 0
    fi

    echo "ERROR: apt-get install failed (arguments: $*)" >&2
    rm -f "$apt_log"
    exit 1
}

declare -a APT_CONFIG_WARNINGS=()
YELLOW=$'\033[33m'
RESET=$'\033[0m'

# https://www.truenas.com/docs/scale/scaletutorials/systemsettings/advanced/developermode/#:~:text=To%20enable%20developer%20mode%2C%20log,install%2Ddev%2Dtools%20command.&text=Running%20install%2Ddev%2Dtools%20removes,for%20development%20environments%20on%20TrueNAS.
# https://www.truenas.com/community/threads/no-more-apt.116340/
sudo install-dev-tools
sudo /usr/local/libexec/disable-rootfs-protection

sudo chmod +x /bin/apt /bin/apt-key /bin/apt-get /bin/apt-cache /bin/apt-config /usr/bin/dpkg

#sudo ~/code/bash_configs/nas/change-iptables-bridge-docker-settings.sh

sudo apt-get update
apt_install -y software-properties-common

# https://docs.docker.com/engine/install/debian/
# Add Docker's official GPG key:
# on 26-beta
# E: Malformed entry 1 in list file /etc/apt/sources.list.d/docker.list (Component)
sudo apt-get update
apt_install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
#curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
#sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add the repository to Apt sources:
#echo \
#  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
#  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
#  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
#sudo apt-get update

#sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# TODO after cobia upgrade missing: hddtemp 
# removed: vagrant clang nvidia-smi
# because it tries to install linux-image-amd64 and libc-i686 that fails becuse of RO /boot in dragonfish and prevents rest of packages to be configured by apt
sudo apt-get update
apt_install -y screen vim  wget gnupg2 ncdu elinks jdupes hfsprogs libicu-dev bzip2 \
    cmake libz-dev libbz2-dev fuse3 libfuse3-3 libfuse3-dev git libattr1-dev libfsapfs-utils \
    dos2unix edac-utils inxi rasdaemon figlet ansible sshpass \
    bc hfsprogs lshw vim-runtime unrar alien bubblewrap
# TODO python breaks on .2 truenas
# sudo apt-get install -y virtualenv python3-venv python3-pip python3-full
sudo apt-get remove -y linux-image-amd64

# disable for dragonfish
#wget -q https://www.virtualbox.org/download/oracle_vbox_2016.asc -O- | sudo apt-key add -
#sudo echo "deb [arch=amd64] http://download.virtualbox.org/virtualbox/debian bullseye contrib" | sudo tee /etc/apt/sources.list.d/virtualbox.list
#sudo apt-get update
#sudo apt-cache madison linux-headers-truenas-amd64
#sudo apt-get install -y linux-headers-truenas-amd64=5.10.70+truenas-1
#sudo apt-get install -y linux-headers-truenas-amd64
#sudo apt-get install -y virtualbox-6.1 dkms

# https://github.com/cli/cli/blob/trunk/docs/install_linux.md
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
&& sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
&& sudo apt-get update \
; apt_install gh -y

if ! grep -qxF /usr/bin/zsh /etc/shells; then
    echo /usr/bin/zsh | sudo tee -a /etc/shells > /dev/null
fi
sudo chsh -s /usr/bin/zsh "$USER" < /dev/tty

# https://linuxnewbieguide.org/how-to-mount-macos-apfs-disk-volumes-in-linux/
sudo cp /mnt/MargokPool/home/sup/code/apfs-fuse/build/apfs-* /usr/local/bin

if ! crontab -l | grep ovh_backup_download; then
    { crontab -l; echo '01 01 * * * /mnt/MargokPool/home/sup/code/bash_configs/nas/cron/proxmox_backup_download.sh'; } | crontab -
    { crontab -l; echo '01 06 * * * /mnt/MargokPool/home/sup/code/bash_configs/nas/cron/ovh_backup_download.sh'; } | crontab -
    { crontab -l; echo '01 15 * * * /mnt/MargokPool/home/sup/code/bash_configs/nas/cron/reolink-rotate-videos.sh'; } | crontab -
    { crontab -l; echo '20 01 * * * /mnt/MargokPool/home/sup/code/bash_configs/nas/cron/proxmox_vm_backups_rotate.sh'; } | crontab -
    { crontab -l; echo '*/10 * * * * /mnt/MargokPool/home/sup/code/bash_configs/nas/cron/git-pull.sh'; } | crontab -
    { crontab -l; echo '* */1 * * * /mnt/MargokPool/home/sup/code/bash_configs/repos/truecharts/update-with-only-git-merge.sh'; } | crontab -
fi
# truetool is depricated. using now heavy tool in truenas cron interface
#if ! sudo crontab -l | grep truetool; then
#    { sudo crontab -l; echo '10 *  * * * /mnt/MargokPool/home/sup/code/truetool/single-run.sh'; } | sudo crontab -
#fi

# user interactive - generate and copy ssh keys
if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen
    ssh-keygen -t ed25519
fi

# TODO check if needed
# TODO check what was this IP previously
#ssh-copy-id root@192.168.1.56

apt_install software-properties-common dirmngr apt-transport-https -y
#sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C4A05888A1C4FA02E1566F859F2A29A569653940
#sudo add-apt-repository "deb http://kryptco.github.io/deb kryptco main" # non-Kali Linux only
#sudo apt-get update
#sudo apt-get install kr -y

date
# TODO find out why below when ssh doesn't complete within timeout it says "Terminated", but hungs and doesn't move further
#timeout 60 ssh-copy-id -i /mnt/MargokPool/home/sup/.ssh/id_rsa.pub -f sup@ovh.bnowakowski.pl
date
cp ssh-config /mnt/MargokPool/home/sup/.ssh/config

apt_install software-properties-common -y
sudo add-apt-repository -y 'deb [arch=amd64] https://repo.zabbix.com/zabbix/7.0/debian/ bullseye main'
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv D913219AB5333005
sudo apt-get update
apt_install -y zabbix-agent2
sudo cp /mnt/MargokPool/home/sup/code/bash_configs/zabbix/zabbix_agent2.conf /etc/zabbix
cd /etc/zabbix/zabbix_agent2.d
sudo ln -sfnT /mnt/MargokPool/home/sup/code/bash_configs /etc/zabbix/zabbix_agent2.d/bash_configs
cd bash_configs
sudo chown sup:sup -R .
mkdir -p repos
sudo chown zabbix:zabbix repos
cd ../
sudo usermod -a -G docker zabbix
sudo mkdir -p /var/lib/zabbix/
sudo chown zabbix:zabbix /var/lib/zabbix
sudo ./bash_configs/zabbix/update-zabbix-metadata.sh
# TODO check why zabbix-add-to-sudoers.sh isn't called
sudo ~/code/bash_configs/nas/zabbix-add-to-sudoers.sh

apt_install unison -y

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
apt_install yq -y 

apt_install -y default-jdk
curl -s https://get.sdkman.io | bash
source ~/.sdkman/src/sdkman-main.sh
yes | sdk update
yes | sdk install kotlin

cd ~/code/bash_configs/nas/zabbix
sudo chown sup:zabbix sie-pomaga
sudo chown sup:zabbix sie-pomaga/*
sudo chmod 774 sie-pomaga
cd ~/code/bash_configs/home-assistant/zabbix
sudo chown sup:zabbix *
cd ~/code/bash_configs/nas/zabbix/archived/is-plex-running
sudo chown sup:zabbix *

# 1password
# https://support.1password.com/install-linux/
curl -sS https://downloads.1password.com/linux/keys/1password.asc | sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main' | sudo tee /etc/apt/sources.list.d/1password.list
sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22/
curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol | sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol
sudo mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22
curl -sS https://downloads.1password.com/linux/keys/1password.asc | sudo gpg --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg
sudo apt-get update
apt_install -y 1password 1password-cli

echo;
echo manual steps:;
echo chage zabbix user id and group id to 990;
echo "press enter when done"
read -r -n 1 -s < /dev/tty
echo

sudo chown -R zabbix:zabbix /var/log/zabbix
sudo chown -R zabbix:zabbix /var/run/zabbix
sudo chown sup:zabbix -R /mnt/MargokPool/home/sup/code/bash_configs/nas/zabbix/sie-pomaga
sudo chown -R zabbix:zabbix /mnt/MargokPool/home/zabbix

cd /mnt/MargokPool/home/sup/code/bash_configs/nas
source bin/activate
pip install gpustat

# https://www.truenas.com/community/threads/how-to-edit-grub_cmdline_linux_default.95245/
# https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/power_management_guide/aspm
# https://forum.proxmox.com/threads/amd-pstate-driver-steps-and-discussion.118873/
sudo midclt call system.advanced.update '{"kernel_extra_options":  "amd_pstate=passive pcie_aspm=force cpufreq.default_governor=powersave"}'

sudo mkdir -p /run/screen; sudo chmod 777 /run/screen

sudo service docker start

codex_installer=$(mktemp)
if curl -fsSL -o "$codex_installer" https://chatgpt.com/codex/install.sh; then
    printf 'n\n' | script -qec "sh '$codex_installer'" /dev/null
    codex_install_status=$?
else
    codex_install_status=$?
fi
rm -f "$codex_installer"
if ((codex_install_status != 0)); then
    exit "$codex_install_status"
fi

if ((${#APT_CONFIG_WARNINGS[@]})); then
    printf '\n%bWARNING: package configuration completed with errors:%b\n' "$YELLOW" "$RESET" >&2
    printf '%b- %s%b\n' "$YELLOW" "${APT_CONFIG_WARNINGS[@]}" "$RESET" >&2
fi
