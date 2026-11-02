#!/bin/bash -x

cd /home/sup/code/bash_configs/ovh
directory="dool"
mkdir -p $directory

# https://www.tecmint.com/dool-monitor-linux-server-performance-process-memory-network/
# cd dool
# git clone https://github.com/scottchiefbaker/dool.git
# cd dool
# sudo ./install.py
# cd ../../

# https://superuser.com/a/1559591
# https://linuxblog.io/dstat-command-in-linux-examples/
sudo dool --time --cpu --disk --io --page --int --sys --load --proc --top-cpu --top-mem --mem --net --swap --output $directory/dool-$(date +"%Y-%m-%d_%H-%M").csv --noupdate 5


