#!/bin/bash

# https://github.com/home-assistant/supervised-installer/issues/304#issuecomment-1611081373

# to build:
# sudo apt install equivs
# equivs-control systemd-resolved.control
# sed -i 's/<package name; defaults to equivs-dummy>/systemd-resolved/g' systemd-resolved.control
# equivs-build systemd-resolved.control

sudo dpkg -i systemd-resolved_1.0_all.deb

