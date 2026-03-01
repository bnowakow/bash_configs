#!/bin/bash

#taint
kubectl taint nodes proxmox4 node-role.kubernetes.io/master:NoSchedule

#untaunt
#kubectl taint nodes proxmox4 node-role.kubernetes.io/master:NoSchedule-

