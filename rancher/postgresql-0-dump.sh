#!/bin/bash -x

# TODO check if root

source lib/postgresql-include.sh

# TODO make sure that clients (i.e. roundcube) has been scaled to 0 before making backup

# below is only dump for manual restore
kubectl exec -it --namespace $pod_namespace $pod_name -- bash -c "mkdir -p $pod_backup_dir"
kubectl exec -it --namespace $pod_namespace $pod_name -- bash -c "export PGPASSWORD=$pgpassword; pg_dump roundcube -U postgres -f $pod_backup_dir/roundcube-$(date +%Y%m%d-%H%M).sql"
kubectl exec -it --namespace $pod_namespace $pod_name -- bash -c "export PGPASSWORD=$pgpassword; pg_dumpall -U postgres -f $pod_backup_dir/dumpall-$(date +%Y%m%d-%H%M).sql"

echo $postgre_pvc_dir/$backup_subdir
ls -lh $postgre_pvc_dir/$backup_subdir
mkdir -p $pvc_dir/backup/posgresql-dump
cp $postgre_pvc_dir/$backup_subdir/* $pvc_dir/backup/posgresql-dump
ls -lh $pvc_dir/backup/posgresql-dump


# below was wip for automatic helm upgrade, it's far from finished
# some resources that could be considered:
# https://medium.com/@andrea.berlingieri42/upgrading-a-postgresql-bitnami-helm-release-11-to-15-2ca447b4580d
# https://github.com/urbica/pg-migrate?tab=readme-ov-file

#kubectl get -o yaml --namespace $pod_namespace pod $pod_name > postgresql-upgrade.yaml
## TODO postgresql-upgrade-modified.yaml was done manually
## diff postgresql-upgrade-orig.yaml postgresql-upgrade-modified.yaml
#kubectl create -f  postgresql-upgrade-modified.yaml

