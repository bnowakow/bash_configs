#!/bin/bash

nordvpn login --token "$(cat .nord_token)"
nordvpn set autoconnect on Czech_Republic p2p

    nordvpn whitelist add port 22        # ssh
    nordvpn whitelist add port 2222      # ssh
    nordvpn whitelist add port 9091      # transmission-daemon
    nordvpn whitelist add port 111       # nfs
    nordvpn whitelist add port 2049  # nfs
    nordvpn whitelist add port 33333 # rpcbind https://serverfault.com/a/823236
    nordvpn whitelist add port $(timeout 10 mount -vvv /mnt/PlexPool/plex 2>&1 | grep TCP | sed 's/.*port\ //' | tail -1) # TODO set static port
    nordvpn whitelist add port 10050 # zabbix-agent2
    nordvpn set protocol tcp
    #nordvpn set technology nordlynx
    #nordvpn set obfuscate on

    # workaround for NordVPN insights api https://github.com/bubuntux/nordvpn/commit/9c338b86f4bf30badcdf7ad18256937d5b203de5
    nordvpn set cybersec off
    nordvpn set dns 1.1.1.1 1.0.0.1

exit_status=1;
while [ ! $exit_status -eq 0 ]; do
	echo "try to connect vpn"
        timeout 60s nordvpn connect --group p2p Czech_Republic || return 1
        exit_status=$?;
done
nordvpn set killswitch on
nordvpn status

echo;echo;

if test $( curl -m 10 -s https://api.nordvpn.com/v1/helpers/ips/insights | jq -r '.["protected"]' ) = "true" ; then
	echo "vpn is connected";
else
	>&2 echo "vpn isn't connected!";
	exit 1;
fi

