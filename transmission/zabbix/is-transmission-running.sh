#!/bin/bash

if sudo service transmission-daemon status | grep Active | grep running> /dev/null; then 
	echo true; 
else 
	echo false; 
fi

