#!/bin/bash

# git submodule add https://github.com/Revenni/zabbix_agent2.git nas/ansible/roles/zabbix_agent2

# https://galaxy.ansible.com/revenni/zabbix_agent2
#ansible-galaxy install revenni.zabbix_agent2

echo "[VM]      on first use for a given host do:"
echo "[VM]      apt update; apt install sudo;"
echo "[VM]      usermod -a -G sudo sup"
echo "[host]    update ~/.ssh/config to include new ip of VM"

# https://www.cherryservers.com/blog/how-to-set-up-ansible-inventory-file
# TODO install nfs-common
# TODO install kr
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook initial-config_playbook.yml -i inventory/proxmox-vms.yml -kK
echo "[VM]      before it's not in ansible install kr, reference in ~/code/bash_configs/nas/provision.sh and kr pair"
ansible-inventory -i inventory/proxmox-vms.yml --list
ansible -m ping all -i inventory/proxmox-vms.yml


ansible-playbook git-config_playbook.yml -i inventory/proxmox-vms.yml
ansible-playbook zabbix-agent2_playbook.yml -i inventory/proxmox-vms.yml -K


