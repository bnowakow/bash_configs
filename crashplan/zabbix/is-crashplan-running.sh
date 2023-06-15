#!/bin/bash

if sudo /usr/local/crashplan/bin/service.sh status | grep running > /dev/null; then 
	echo true; 
else 
	echo false;
fi

