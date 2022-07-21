#!/bin/bash

sudo update-grub
sudo cp /boot/grub/grub.cfg grub-old.cfg

file_length=$(wc -l grub-old.cfg | cut -d ' ' -f 1)
line_number=$(grep -n 'export linux_gfx_mode' grub-old.cfg | cut -d : -f 1)
tail_numbers=$((file_length-line_number))

head -n $line_number grub-old.cfg > grub.cfg
cat grub-old-menuentries.cfg >> grub.cfg
tail -n $tail_numbers grub-old.cfg >> grub.cfg

sudo cp grub.cfg /boot/grub/grub.cfg

grub-script-check /boot/grub/grub.cfg
echo $?

