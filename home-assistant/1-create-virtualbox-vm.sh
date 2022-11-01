#!/bin/bash

# https://andreafortuna.org/2019/10/24/how-to-create-a-virtualbox-vm-from-command-line/
MACHINENAME=home-assistant
dir=/mnt/MargokPool/home/sup/code/home-assistant-vagrant

# https://github.com/home-assistant/operating-system/releases
# TODO get latest vdi automatically, curling website doesn't work since there's a lot of assets and you need to ajax them
rm *.vdi*
wget https://github.com/home-assistant/operating-system/releases/download/9.2/haos_ova-9.2.vdi.zip
unzip *vdi.zip
vdi=$(ls *.vdi)

VBoxManage createvm --name $MACHINENAME --ostype "Linux26_64" --register --basefolder $dir

mv $vdi $MACHINENAME

# https://computingforgeeks.com/manage-virtualbox-vms-from-command-line-using-vboxmanage/
vboxmanage modifyvm $MACHINENAME --memory 4096 --cpus 2 --rtcuseutc on

VBoxManage storagectl $MACHINENAME --name "SATA Controller" --add sata --controller IntelAhci

#VBoxManage storageattach $MACHINENAME --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium  $dir/haos_ova-9.0.vdi
VBoxManage storageattach $MACHINENAME --storagectl "SATA Controller" --port 0 --device 0 --type hdd --nonrotational on --discard on --medium $dir/$MACHINENAME/$vdi

# https://www.home-assistant.io/installation/linux
# https://www.virtualbox.org/manual/ch03.html
VBoxManage modifyvm $MACHINENAME --firmware efi

# https://devminz.github.io/posts/devops/virtualbox-cli-vm-bridged-networking/
#VBoxManage modifyvm vmtest --nic1 bridged --nictype1 82545EM --bridgeadapter1 vmtestbr1

VBoxManage modifyvm $MACHINENAME --nic1 nat

# TODO manual said 'Then go to “Audio” and choose “Intel HD Audio” as Audio Controller.' can't find it so added below instead
# https://subscription.packtpub.com/book/virtualization-and-cloud/9781847199140/8/ch08lvl1sec106/time-for-action-enabling-audio-on-your-remote-virtual-machine
VBoxManage modifyvm $MACHINENAME --audio oss --audiocontroller ac97

# https://www.thomas-krenn.com/en/wiki/Headless_Mode_for_Virtual_Machines_of_VirtualBox
VBoxHeadless -s $MACHINENAME &
#VBoxHeadless --startvm $MACHINENAME
# workaround for machine to boot
sleep 10;

# https://superuser.com/a/1558566
# sudo lsof -i -P -n | grep LISTEN | grep 2223; https://www.cyberciti.biz/faq/unix-linux-check-if-port-is-in-use-command/
# vboxmanage showvminfo --details $MACHINENAME | grep NIC
VBoxManage controlvm $MACHINENAME natpf1 "ha-web,tcp,,8123,,8123"
VBoxManage controlvm $MACHINENAME natpf1 "ssh-add-on,tcp,,22222,,22222"
VBoxManage controlvm $MACHINENAME natpf1 "ssh,tcp,,2223,,22"

