#!/bin/bash

# web terminal in ha works fine, but ssh not, description of a problem: https://stackoverflow.com/questions/17931764/zsh-tab-completion-messes-up-command-line-formatting
# as workaround turning off two plugins that causes most side effectcs in ssh terminal

cd /mnt/MargokPool/home/sup/code/bash_configs/home-assistant
#ssh root@192.168.1.67  
vagrant ssh -c "if grep '^source /usr' .zshrc >/dev/null; then sed -i 's/^source\ \\//#source\ \\//' .zshrc; echo 'changed'; else echo 'change already in place'; fi"

