#!/bin/bash

# possible conflicts while pulling: crashplan, docker-mailserver (docker-compose, Makefile), homer (config), medihunter, zabbix-scripts (.gitignore)

dirs=("/mnt/MargokPool/home/sup/code/docker-jdupes-gui" \
    "/mnt/MargokPool/home/sup/code/bash_configs/repos/truecharts" \
    "/mnt/MargokPool/home/sup/code/bash_configs/repos/truenas" \
    "/mnt/MargokPool/home/sup/code/docker-mailserver" \
    "/mnt/MargokPool/home/sup/code/universal-trakt-scrobbler" \
    "/mnt/MargokPool/home/sup/code/homer"
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

