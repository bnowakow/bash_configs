#!/bin/bash

# Namespace: apps-cloud-casa5
# App name: cloudcasa5-1
# cluster_id: '6938435f0c7d143c28eb3a0f'
kubectl delete namespace apps-cloudcasa  
kubectl delete namespace cloudcasa-io

# https://stackoverflow.com/a/75905689 
# kubectl patch ns  apps-cloud-casa5 -p '{"metadata":{"finalizers":null}}'

# if above din't work try: kubectl get apiservice | grep -n namespace
# kubectl delete apiservice 

# if above wouldn't work that did for me: https://stackoverflow.com/a/63395937
# wget https://gist.githubusercontent.com/jossef/a563f8651ec52ad03a243dec539b333d/raw/8c7dd29e95a9578375190d1c9b704eddba0639f9/force-delete-k8s-namespace.py
# python3 force-delete-k8s-namespace.py longhorn-system

