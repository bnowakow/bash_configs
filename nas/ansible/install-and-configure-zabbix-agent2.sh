#!/bin/bash

# git submodule add https://github.com/Revenni/zabbix_agent2.git nas/ansible/roles/zabbix_agent2

# https://galaxy.ansible.com/revenni/zabbix_agent2
#ansible-galaxy install revenni.zabbix_agent2

# TODO automate below
echo "[VM]                      on first use for a given host do:"
echo "[VM][proxmox][as root]    adduser sup"
echo "[VM]                      apt update; apt install sudo;"
echo "[VM]                      usermod -a -G sudo sup"
echo "press enter when done"
read;

# https://www.cherryservers.com/blog/how-to-set-up-ansible-inventory-file
# TODO install nfs-common
# TODO automate below
echo "[VM]              on first use for a given host do:"
echo "[VM][as sup]      install kr and kr pair: curl https://bnowakow.github.io/krypt/kr.sh | sh && kr pair; kr sshconfig"
echo "[host]            check if you can ssh to vm since known_hosts might have a conflict if reworking previously existing machine"
echo "[iPhone]          open kr on iPhone and remove last known hosts to github on kr app"
echo "press enter when done"
read;

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook initial-config_playbook.yml -i inventory/proxmox-vms.yml -kK
ansible-inventory -i inventory/proxmox-vms.yml --list
ansible -m ping all -i inventory/proxmox-vms.yml


ansible-playbook git-config_playbook.yml -i inventory/proxmox-vms.yml
# TODO https://askubuntu.com/questions/13065/how-do-i-fix-the-gpg-error-no-pubkey
# TODO automate below
echo "add to playbook sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys D913219AB5333005 before installing zabbix"
ansible-playbook zabbix-agent2_playbook.yml -i inventory/proxmox-vms.yml -K
# TODO automate below
echo "[VM]              before it's not in ansible set /bin/bash for zabbix account and create its user directrory and chown it to zabbix"
echo "[VM]              run ~/code/bash_configs/zabbix/update-zabbix-metadata.sh"
echo '[VM][proxmox]     sudo bash -c "$(wget -qLO - https://github.com/tteck/Proxmox/raw/main/misc/post-pve-install.sh)"'
echo "[VM]              follow https://github.com/sorin-ionescu/prezto"
# TODO add apt upgrade and upgrade zprezto"
echo "press enter when done"
read;

