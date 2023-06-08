#!/bin/bash

# git submodule add https://github.com/Revenni/zabbix_agent2.git nas/ansible/roles/zabbix_agent2

# https://galaxy.ansible.com/revenni/zabbix_agent2
#ansible-galaxy install revenni.zabbix_agent2

# https://www.cherryservers.com/blog/how-to-set-up-ansible-inventory-file
ansible-inventory -i inventory/proxmox-vms.yml --list
ansible -m ping all -i inventory/proxmox-vms.yml

ansible-playbook zabbix-agent2_playbook.yml -i inventory/proxmox-vms.yml -K
ansible-playbook git-config_playbook.yml -i inventory/proxmox-vms.yml


