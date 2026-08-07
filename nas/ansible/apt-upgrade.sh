#!/bin/bash

ansible-playbook apt-upgrade_playbook.yml -i inventory/proxmox-vms.yml -K
