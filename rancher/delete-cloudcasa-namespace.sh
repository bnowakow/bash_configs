#!/bin/bash

# Namespace: apps-cloud-casa5
# App name: cloudcasa5-1
# cluster_id: '6714c10d25c7131f9f9d44df'
kubectl delete namespace apps-cloud-casa5  

# https://stackoverflow.com/a/75905689 
# kubectl patch ns  apps-cloud-casa5 -p '{"metadata":{"finalizers":null}}'

