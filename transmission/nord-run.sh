#!/bin/bash

export HOME=/home/sup

# TODO check if .nord_token exists and if not output error

nordvpn login --token "$(cat .nord_token)"
nordvpn set autoconnect on Czech_Republic p2p
nordvpn set lan-discovery enabled

nordvpn set protocol tcp
nordvpn set technology openvpn
#nordvpn set technology nordlynx
#nordvpn set obfuscate on

# workaround for NordVPN insights api https://github.com/bubuntux/nordvpn/commit/9c338b86f4bf30badcdf7ad18256937d5b203de5
nordvpn set cybersec off
#nordvpn set dns 8.8.8.8 1.1.1.1

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

