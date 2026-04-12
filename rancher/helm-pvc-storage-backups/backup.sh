#!/bin/bash

# TODO make sure runs as root

backup_dir="/home/sup/code/bash_configs/rancher/helm-pvc-storage-backups"
pvc_dir_prefix="/var/lib/rancher/k3s/storage"

namespace="apps"
underscore="_"
app="homer"
pvc_dir_middle="pvc-80dc3cac-61fb-4222-849b-2197bac3a9df_"
pvc_dir_suffix="-config"

source_dir="$pvc_dir_prefix/$pvc_dir_middle$namespace-$app$underscore$app$pvc_dir_suffix"
destination_dir="$backup_dir/$app"

rsync -a -v --progress $source_dir $destination_dir



