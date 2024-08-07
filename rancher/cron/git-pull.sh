#!/bin/bash

# possible conflicts while pulling: crashplan, docker-mailserver (docker-compose, Makefile), homer (config), medihunter, zabbix-scripts (.gitignore)

dirs=("/home/sup/code/bash_configs/repos/truecharts" \
    "/home/sup/code/bash_configs/repos/zabbix" \
    "/home/sup/code/bash_configs/repos/aa-YoutubeDL-Material/youtubedl-material" \
    "/home/sup/code/bash_configs/repos/docker-mailserver-helm" \
    "/home/sup/code/bash_configs/repos/partner-charts" \
)

for dir in ${dirs[@]}; do
    echo $dir
    cd $dir
    if [ -f "git-pull.sh" ]; then
        ./git-pull.sh;
    else 
        git pull
    fi
    git status | grep branch
    # TODO check if there was a merge conflict
    echo;
done

