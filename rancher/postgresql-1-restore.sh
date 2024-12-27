#!/bin/bash -x

# TODO check if root

source lib/postgresql-include.sh

# below is only restore for manual restore
kubectl exec -it --namespace $pod_namespace $pod_name -- bash -c "mkdir -p $pod_backup_dir"
cp $pvc_dir/backup/posgresql-dump/* $postgre_pvc_dir/$backup_subdir
# TODO check if tail -n1 is getting latest backup file
dump_file_name=$(cd $pvc_dir/backup/posgresql-dump/; ls -1 roundcube-* | tail -n1)

user_password=$(cat .posgresql_roundcube_password)
kubectl exec -it --namespace $pod_namespace $pod_name -- bash -c "export PGPASSWORD=$pgpassword; echo create user roundcube with password \'$user_password\' | psql -U postgres; echo create database roundcube with owner roundcube | psql -U postgres"
kubectl exec -it --namespace $pod_namespace $pod_name -- bash -c "export PGPASSWORD=$user_password; psql -U roundcube -f $pod_backup_dir/$dump_file_name"

