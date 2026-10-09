#!/bin/bash

echo "from inside minio console"

# mc alias set --insecure minio-admin https://ovh.bnowakowski.pl:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD
# mc alias set minio-admin https://minio.nas.localdomain.bnowakowski.pl $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD

# when using ovh port redirect --insecure needs to be added to each of below
# mc mb minio-admin/cloudcasa-backups 
# mc rm --recursive --dangerous --force --older-than 60d export/cloudcasa-backups
mc ilm rule add minio-admin/cloudcasa-backups --expire-days "32"
mc ilm rule ls minio-admin/cloudcasa-backups
mc ilm rule edit --id d1fe0ngdvfatchg9hek0 --expire-days "7"  minio-admin/cloudcasa-backups

# below was used for error "Error is unable to create shared content manager: error loading indexes: error downloading indexes" and 
# "unable to decrypt content: cipher: message authentication failed" in cloudcasa that occured after rm --older-than 10d. 
# it deletes and re-creates a bucket
# mc rb --force minio-admin/cloudcasa-backups
# mc mb minio-admin/cloudcasa-backups

