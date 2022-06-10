#!/bin/bash

sed -i "s/,\ \"bridge\"[^}]*//" /etc/docker/daemon.json;
sed -i "s/,\ \"iptables\"[^}]*//" /etc/docker/daemon.json; 
service docker restart;

