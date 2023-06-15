#!/bin/bash -x

cd /mnt/MargokPool/home/sup/code
for dir in `ls -d $PWD/*`; do echo $dir; git config --global --add safe.directory $dir; done

# TODO do a function to not repeat this one line
cd /mnt/MargokPool/home/sup/code/bash_configs/repos
for dir in `ls -d $PWD/*`; do echo $dir; git config --global --add safe.directory $dir; done

