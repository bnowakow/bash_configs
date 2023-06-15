#!/bin/bash

if nordvpn status | grep Status | grep Connected > /dev/null; then 
	echo true; 
else 
	echo false; 
fi

