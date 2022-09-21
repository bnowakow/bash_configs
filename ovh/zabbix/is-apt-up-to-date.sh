#!/bin/bash

ssh zabbix-apt@ovh.bnowakowski.pl sudo ls; sudo /bin/apt-get update; sudo /bin/apt-get --simulate upgrade

