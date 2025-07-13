#!/bin/bash

echo "from inside minio console"

# mc alias set --insecure minio-admin https://ovh.bnowakowski.pl:9000 $MINIO_ROOT_USERNAME $MINIO_ROOT_PASSWORD

# mc mb minio-admin/cloudcasa-backups --insecure
# mc rm --recursive --dangerous --force --older-than 60d export/cloudcasa-backups
mc ilm rule add minio-admin/cloudcasa-backups --expire-days "32" --insecure
mc ilm rule ls minio-admin/cloudcasa-backups --insecure
mc ilm rule edit --id d1fe0ngdvfatchg9hek0 --expire-days "7" --insecure minio-admin/cloudcasa-backups

