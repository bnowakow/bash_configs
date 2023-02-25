#!/bin/bash

# https://computingforgeeks.com/step-by-step-guide-on-using-existing-virtual-machines-with-vagrant/
# https://subscription.packtpub.com/book/cloud-&-networking/9781784393748/1/ch01lvl1sec14/using-existing-virtual-machines-with-vagrant

MACHINENAME=home-assistant
dir=/mnt/MargokPool/home/sup/code/home-assistant-vagrant

ssh-keygen -f "/mnt/MargokPool/home/sup/.ssh/known_hosts" -R "[localhost]:2223"
# if doing vagrantbox do 1. create root and vagrant accounts 2. set advanced in user preferences 3. install SSH & Web Terminal add-on 4. turn it during boot and enable other switches 5. change username and password to vagrant in add-on configuration 6. start add-on
ssh -v -i /mnt/MargokPool/home/sup/.ssh/id_rsa -p 2223 vagrant@localhost

vboxmanage controlvm home-assistant poweroff

vagrant_username=bnowakow
vagrant_version=$(ls $MACHINENAME/*vdi | sed 's/.*-//' | sed 's/.vdi//')
vagrant_provider=virtualbox
vagrant_token=$(cat ~/.vagrant.d/data/vagrant_login_token)

rm $MACHINENAME.box
vagrant package --base=$MACHINENAME --output=$MACHINENAME.box
vagrant box add --force --name=$vagrant_username/$MACHINENAME $MACHINENAME.box

VBoxManage unregistervm $MACHINENAME -delete

vagrant cloud publish --release --force $vagrant_username/$MACHINENAME $vagrant_version $vagrant_provider $MACHINENAME.box

echo When restoring HA backup/snapshot: https://community.home-assistant.io/t/add-ons-not-working-properly-after-snapshot-restore/449796/18

