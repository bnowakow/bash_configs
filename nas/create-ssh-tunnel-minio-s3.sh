#!/bin/bash -x

# https://linuxize.com/post/how-to-setup-ssh-tunneling/#remote-port-forwarding

local_port=9000

remote_port=9000
remote_host=ovh.bnowakowski.pl

ssh -v -R $remote_port:127.0.0.1:$local_port -N -f $remote_host
echo $?

