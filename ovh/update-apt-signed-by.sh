#!/bin/bash

curl -fsSL "https://packages.sury.org/apache2/apt.gpg" | \
	sudo gpg --dearmor -o /usr/share/keyrings/apache2-keyring.gpg  && \
	sudo apt update

curl -fsSL "https://packages.sury.org/php/apt.gpg" | \
        sudo gpg --dearmor -o /usr/share/keyrings/sury-keyring.gpg  && \
        sudo apt update

curl -fsSL "https://apt.hestiacp.com/pubkey.gpg" | \
        sudo gpg --dearmor -o /usr/share/keyrings/hestia-keyring.gpg  && \
        sudo apt update

