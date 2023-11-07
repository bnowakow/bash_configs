#!/bin/bash -x

# https://stackoverflow.com/a/60395957
NS=`sudo k3s kubectl get ns |grep Terminating | awk 'NR==1 {print $1}'`
sudo k3s kubectl get namespace "$NS" -o json   | tr -d "\n" | sed "s/\"finalizers\": \[[^]]\+\]/\"finalizers\": []/" | sudo k3s kubectl replace --raw /api/v1/namespaces/$NS/finalize -f -

