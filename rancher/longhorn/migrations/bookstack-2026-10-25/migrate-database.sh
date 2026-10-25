#!/usr/bin/env bash
# Variables in quoted scripts expand only inside the database container.
# shellcheck disable=SC2016
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
k=(kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml)
ns=apps-bookstack
private=/tmp/longhorn-bookstack-originals
"${k[@]}" -n "$ns" get deployment bookstack -o json | jq -e '.spec.replicas==1 and .status.availableReplicas==1 and any(.spec.template.spec.volumes[];.persistentVolumeClaim.claimName=="bookstack-config-longhorn-rwo")' >/dev/null
"${k[@]}" -n "$ns" get deployment bookstack-mariadb -o json | jq -e 'any(.spec.template.spec.volumes[];.persistentVolumeClaim.claimName=="bookstack-mariadb-data")' >/dev/null
for claim in bookstack-config bookstack-mariadb-data; do
 "${k[@]}" -n "$ns" get pvc "$claim" -o json > "$private/$claim-original.json"
 pv="$(jq -r .spec.volumeName "$private/$claim-original.json")"
 "${k[@]}" -n "$ns" annotate pvc "$claim" helm.sh/resource-policy=keep --overwrite
 "${k[@]}" patch pv "$pv" --type=merge -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
done
stopped=0
cutover=0
# Called by EXIT; helpers must be removed before restoring source writers.
# shellcheck disable=SC2317
recover_failure() {
 result=$?
 if [ "$result" -ne 0 ] && [ "$stopped" -eq 1 ] && [ "$cutover" -eq 0 ]; then
  echo 'Pre-cutover failure: stop helper and restore original database with persistent app config' >&2
  "${k[@]}" -n "$ns" delete pod bookstack-db-transfer-20261025 --ignore-not-found --wait=true || true
  "${k[@]}" -n "$ns" scale deployment bookstack-mariadb --replicas=1 || true
  "${k[@]}" -n "$ns" scale deployment bookstack --replicas=1 || true
 fi
 exit "$result"
}
trap recover_failure EXIT
"${k[@]}" -n "$ns" scale deployment bookstack --replicas=0
stopped=1
gone=0
for ((i=0;i<4;i++)); do
 if "${k[@]}" -n "$ns" wait --for=delete pod -l 'app.kubernetes.io/name=bookstack' --timeout=55s; then gone=1; break; fi
done
[ "$gone" -eq 1 ] || exit 1
"${k[@]}" -n "$ns" exec deployment/bookstack-mariadb -- sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot -NBe '\''SELECT CONCAT("CHECKSUM TABLE `bookstack`.`",TABLE_NAME,"` EXTENDED;") FROM information_schema.TABLES WHERE TABLE_SCHEMA="bookstack" AND TABLE_TYPE="BASE TABLE" ORDER BY TABLE_NAME;'\''' > "$private/bookstack-checksums.sql"
"${k[@]}" -n "$ns" exec -i deployment/bookstack-mariadb -- sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot -N' < "$private/bookstack-checksums.sql" > "$private/database-source-checksums.txt"
[ -s "$private/database-source-checksums.txt" ]
if grep -q NULL "$private/database-source-checksums.txt"; then echo "Unverifiable source table checksum" >&2; exit 1; fi
"${k[@]}" -n "$ns" scale deployment bookstack-mariadb --replicas=0
gone=0
for ((i=0;i<4;i++)); do
 if "${k[@]}" -n "$ns" wait --for=delete pod -l 'app.kubernetes.io/name=mariadb' --timeout=55s; then gone=1; break; fi
done
[ "$gone" -eq 1 ] || exit 1
"${k[@]}" create -f "$here/db-helper.json"
"${k[@]}" -n "$ns" wait --for=condition=Ready pod/bookstack-db-transfer-20261025 --timeout=55s
"${k[@]}" -n "$ns" cp "$here/copy-database.py" bookstack-db-transfer-20261025:/tmp/copy-database.py -c transfer
"${k[@]}" -n "$ns" exec bookstack-db-transfer-20261025 -c transfer -- python -u /tmp/copy-database.py --replace-staging
"${k[@]}" -n "$ns" exec bookstack-db-transfer-20261025 -c transfer -- cat /tmp/database-manifest.json > "$private/database-manifest.json"
"${k[@]}" -n "$ns" cp "$private/bookstack-checksums.sql" bookstack-db-transfer-20261025:/tmp/bookstack-checksums.sql -c database
"${k[@]}" -n "$ns" exec -i bookstack-db-transfer-20261025 -c database -- sh -s < "$here/verify-database.sh" > "$private/database-isolated-verification.txt"
cat "$private/database-isolated-verification.txt"
"${k[@]}" -n "$ns" exec bookstack-db-transfer-20261025 -c database -- cat /tmp/database-checksums.txt > "$private/database-target-checksums.txt"
diff -u "$private/database-source-checksums.txt" "$private/database-target-checksums.txt"
echo 'All source/target BookStack table checksums match; target database stopped'
# The following explicit gate keeps the app stopped until backup checks finish.
touch "$private/database-copy-verified"
while [ ! -e "$private/backup-and-restore-verified" ]; do sleep 2; done
"${k[@]}" -n "$ns" delete pod bookstack-db-transfer-20261025 --wait=true
cutover=1
cp "$here/final-values.yaml" "$root/fleet/apps/bookstack/values.yaml"
"$here/../pilot-2026-10-24/apply-bundle.sh" bookstack rancher/fleet/apps/bookstack
for ((i=0;i<90;i++)); do
 if "${k[@]}" -n "$ns" get deployment bookstack-mariadb -o json | jq -e '.spec.replicas==1 and any(.spec.template.spec.volumes[];.persistentVolumeClaim.claimName=="bookstack-mariadb-data-longhorn-rwo")' >/dev/null; then break; fi
 sleep 2
done
for deployment in bookstack-mariadb bookstack; do
 success=0
 for ((i=0;i<6;i++)); do
  if "${k[@]}" -n "$ns" rollout status "deployment/$deployment" --timeout=55s; then success=1; break; fi
 done
 [ "$success" -eq 1 ] || exit 1
done
echo 'BookStack and MariaDB running with both Longhorn claims'
