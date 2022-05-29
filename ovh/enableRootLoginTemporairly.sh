#!/bin/bash

change_duration=3600;
change_duration=5;

function ensure_running_as_root {
	whoami=$(whoami);
	if [ "root" != "$whoami" ]; then
		echo "$0 must be run as root";
		exit 1;
	fi
}

function change_sshd_permit_root_login {
	sed -i -e "s/\(PermitRootLogin\) .*/\1 $1/" /etc/ssh/sshd_config;
	/etc/init.d/ssh reload;
	return $?;
}

function uncomment_ssh_authorized_keys {
	echo uncomment_ssh_authorized_keys;	
	sed -i -e "s/^\#//" /root/.ssh/authorized_keys
	return $?;
}

function comment_ssh_authorized_keys {
	echo comment_ssh_authorized_keys;
	sed -i -e "s/^/\#/" /root/.ssh/authorized_keys 
}

function enable_root_login {
	echo enable_root_login;
	change_sshd_permit_root_login yes;
	uncomment_ssh_authorized_keys;
}

function disable_root_login {
	echo disable_root_login;
	change_sshd_permit_root_login no;
	comment_ssh_authorized_keys;
}

ensure_running_as_root;
date;
enable_root_login;
sleep $change_duration;
disable_root_login;
date;
