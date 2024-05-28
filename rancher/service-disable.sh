#!/bin/bash

sudo systemctl stop k3s
sudo systemctl disable k3s
sudo systemctl status k3s

