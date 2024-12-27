#!/bin/bash -x

# TODO check if root

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

app="postgresql"
# TODO in helm-upgrade-apps.sh there's real method of getting namespace
pod_namespace="apps-$app"
# TODO also hardcode as above
pod_name="$app-0"

# https://medium.com/@andrea.berlingieri42/upgrading-a-postgresql-bitnami-helm-release-11-to-15-2ca447b4580d
pgpassword=$(kubectl get secret --namespace $pod_namespace $app -o jsonpath="{.data.postgres-password}" | base64 --decode)
bitnami_local_version=$(kubectl exec --namespace $pod_namespace $pod_name -- bash -c 'echo $APP_VERSION')

pod_dir_prefix="/bitnami/postgresql"
backup_subdir="dump"
pod_backup_dir="$pod_dir_prefix/$backup_subdir"

pvc_dir="/var/lib/rancher/k3s/storage"
# TODO it would be better to read from pvc via kubectl
postgre_pvc_dir_suffix=$(ls /var/lib/rancher/k3s/storage/ | grep postgresql_data-$pod_name)
postgre_pvc_dir=$pvc_dir/$postgre_pvc_dir_suffix

