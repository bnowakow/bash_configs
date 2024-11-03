#!/bin/bash

# https://stackoverflow.com/a/66362156
echo run as root, export kubeconfig

kubectl -n cert-manager apply -f test-certificate-stag.yaml

