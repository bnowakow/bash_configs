#!/usr/bin/env bash
# Shell variables in quoted scripts intentionally expand inside PostgreSQL pods.
# shellcheck disable=SC2016
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
k=(kubectl --kubeconfig "${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}")
ns="apps-zabbix"
backup=/tmp/longhorn-zabbix-originals
clients=(zabbix-zabbix-server zabbix-zabbix-web zabbix-zabbix-webservice)
source=postgresql-data-zabbix-postgresql-0
target=zabbix-postgresql-data-longhorn-rwo
helper=zabbix-postgres-transfer-20261025
slot=lh_zabbix_migration_20261025
guard_app=longhorn-zabbix-slot-20261025
mkdir -p "$backup"
psql_source() {
 "${k[@]}" --request-timeout=30s -n "$ns" exec zabbix-postgresql-0 -c postgresql -- sh -c \
 'exec psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -v ON_ERROR_STOP=1 -c "$1"' sh "$1"
}
"${k[@]}" --request-timeout=15s get --raw=/readyz >/dev/null
"${k[@]}" -n "$ns" get sts zabbix-postgresql -o json > "$backup/source-statefulset.json"
jq -e --arg source "$source" '.spec.replicas==1 and .status.readyReplicas==1 and any(.spec.template.spec.volumes[];.persistentVolumeClaim.claimName==$source)' "$backup/source-statefulset.json" >/dev/null
"${k[@]}" -n "$ns" get pvc "$target" -o json | jq -e '.status.phase=="Bound" and .spec.storageClassName=="longhorn-rwo-2replicas"' >/dev/null
"${k[@]}" -n "$ns" get pvc "$source" -o json > "$backup/source-pvc.json"
pv="$(jq -r '.spec.volumeName' "$backup/source-pvc.json")"
"${k[@]}" -n "$ns" annotate pvc "$source" helm.sh/resource-policy=keep --overwrite
"${k[@]}" patch pv "$pv" --type=merge -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
for client in "${clients[@]}"; do
 "${k[@]}" -n "$ns" get deployment "$client" -o json > "$backup/$client.json"
 jq -e '.spec.replicas==1 and .status.availableReplicas==1' "$backup/$client.json" >/dev/null
done
"${k[@]}" -n "$ns" get cronjob zabbix-nodesclean -o json > "$backup/source-cronjob.json"
original_suspend="$(jq -r '.spec.suspend//false' "$backup/source-cronjob.json")"
stopped=0
cutover=0
guard_pid=''
# Called indirectly by EXIT.
# shellcheck disable=SC2317
recover_failure() {
 result=$?
 psql_source "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name='$guard_app' AND pid<>pg_backend_pid();" >/dev/null 2>&1 || true
 [ -z "$guard_pid" ] || kill "$guard_pid" 2>/dev/null || true
 if [ "$result" -ne 0 ] && [ "$stopped" -eq 1 ] && [ "$cutover" -eq 0 ]; then
  echo 'Pre-cutover failure: restoring original PostgreSQL and Zabbix writers' >&2
  "${k[@]}" -n "$ns" scale statefulset zabbix-postgresql --replicas=1 || true
  for client in "${clients[@]}"; do "${k[@]}" -n "$ns" scale deployment "$client" --replicas=1 || true; done
  "${k[@]}" -n "$ns" patch cronjob zabbix-nodesclean --type=merge -p "{\"spec\":{\"suspend\":$original_suspend}}" || true
 fi
 exit "$result"
}
trap 'recover_failure' EXIT
"${k[@]}" create -f "$here/transfer-pod.json"
"${k[@]}" -n "$ns" wait --for=condition=Ready "pod/$helper" --timeout=55s
"${k[@]}" -n "$ns" patch cronjob zabbix-nodesclean --type=merge -p '{"spec":{"suspend":true}}'
stopped=1
for client in "${clients[@]}"; do "${k[@]}" -n "$ns" scale deployment "$client" --replicas=0; done
for client in "${clients[@]}"; do
 selector="$(jq -r '.spec.selector.matchLabels|to_entries|map("\(.key)=\(.value)")|join(",")' "$backup/$client.json")"
 gone=0
 for ((attempt=0;attempt<5;attempt++)); do
  if "${k[@]}" -n "$ns" wait --for=delete pod -l "$selector" --timeout=55s; then gone=1; break; fi
 done
 [ "$gone" -eq 1 ] || { echo 'A Zabbix writer did not stop' >&2; exit 1; }
done
[ "$(psql_source "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND backend_type='client backend' AND pid<>pg_backend_pid();")" = 0 ] || { echo 'Unexpected remaining database clients; inspect before backup' >&2; exit 1; }
psql_source "SELECT 'system_identifier='||system_identifier FROM pg_control_system(); SELECT 'schema='||mandatory||':'||optional FROM dbversion; SELECT 'recovery='||pg_is_in_recovery(); SELECT 'public_tables='||count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p');" > "$backup/database-baseline.txt"
# A temporary slot reserves WAL for fetch mode without changing hba/settings.
# Same psql session for both -c commands; the slot drops on session termination.
"${k[@]}" -n "$ns" exec zabbix-postgresql-0 -c postgresql -- sh -c \
 'PGOPTIONS="-c statement_timeout=0 -c idle_in_transaction_session_timeout=0" PGAPPNAME=longhorn-zabbix-slot-20261025 exec psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -c "SELECT pg_create_physical_replication_slot('"'"'lh_zabbix_migration_20261025'"'"',true,true);" -c "SELECT pg_sleep(7200);"' \
 > "$backup/slot-guard.log" 2>&1 &
guard_pid=$!
slot_ready=0
for ((attempt=0;attempt<30;attempt++)); do
 if [ "$(psql_source "SELECT count(*) FROM pg_replication_slots WHERE slot_name='$slot' AND temporary AND restart_lsn IS NOT NULL;")" = 1 ]; then slot_ready=1; break; fi
 sleep 1
done
[ "$slot_ready" -eq 1 ] || { echo 'Temporary WAL retention slot did not appear' >&2; exit 1; }
echo 'Starting native basebackup: 4MiB/s, spread checkpoint, SHA256 manifest, WAL fetch'
"${k[@]}" -n "$ns" exec zabbix-postgresql-0 -c postgresql -- sh -c \
 'exec pg_basebackup -U "$POSTGRES_USER" -D - -Ft -X fetch --max-rate=4M --checkpoint=spread --manifest-checksums=SHA256 --label=longhorn-zabbix-20261025' \
 | "${k[@]}" -n "$ns" exec -i "$helper" -- sh -ec \
 'tar --extract --file=- --preserve-permissions --same-owner --directory=/target/pgdata; sync -f /target/pgdata'
echo 'Native basebackup transfer completed'
psql_source "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name='$guard_app' AND pid<>pg_backend_pid();" >/dev/null
wait "$guard_pid" || true
guard_pid=''
[ "$(psql_source "SELECT count(*) FROM pg_replication_slots WHERE slot_name='$slot';")" = 0 ] || { echo 'Temporary slot remains; inspect before proceeding' >&2; exit 1; }
"${k[@]}" -n "$ns" exec -i "$helper" -- sh -s < "$here/verify-target.sh" > "$backup/target-verification.log"
cat "$backup/target-verification.log"
grep -E '^(system_identifier|schema|recovery|public_tables)=' "$backup/target-verification.log" > "$backup/database-target.txt"
diff -u "$backup/database-baseline.txt" "$backup/database-target.txt"
echo 'Target database identity/schema/table inventory match source; isolated recovery passed'
# Keep a private evidence copy; a live data directory must not advertise an old manifest.
"${k[@]}" -n "$ns" exec "$helper" -- cat /target/pgdata/backup_manifest > "$backup/backup_manifest.json"
"${k[@]}" -n "$ns" exec "$helper" -- rm /target/pgdata/backup_manifest
"${k[@]}" -n longhorn-system create job --from=cronjob/nas-daily-backup zabbix-nas-backup-20261025
backup_complete=0
for ((attempt=0;attempt<30;attempt++)); do
 if "${k[@]}" -n longhorn-system wait --for=condition=complete job/zabbix-nas-backup-20261025 --timeout=55s; then backup_complete=1; break; fi
 if "${k[@]}" -n longhorn-system get job zabbix-nas-backup-20261025 -o json | jq -e '(.status.failed//0)>0' >/dev/null; then break; fi
done
[ "$backup_complete" -eq 1 ] || { echo 'NAS backup did not complete; refusing cutover' >&2; exit 1; }
"${k[@]}" -n longhorn-system get backups.longhorn.io -o json > "$backup/backups.json"
"${k[@]}" -n longhorn-system get job zabbix-nas-backup-20261025 -o json > "$backup/backup-job.json"
"${k[@]}" -n "$ns" get pvc "$target" -o json > "$backup/target-pvc.json"
python3 - "$backup" <<'PY'
import pathlib,json,sys
p=pathlib.Path(sys.argv[1]);volume=json.loads((p/'target-pvc.json').read_text())['spec']['volumeName'];start=json.loads((p/'backup-job.json').read_text())['status']['startTime']
bs=[b for b in json.loads((p/'backups.json').read_text())['items'] if b.get('status',{}).get('volumeName')==volume and b['status']['state']=='Completed' and b['status'].get('backupCreatedAt','')>=start]
assert bs,'No fresh Completed target backup';b=max(bs,key=lambda x:x['status']['backupCreatedAt']);(p/'backup-summary.json').write_text(json.dumps({'volume':volume,'backup':b['metadata']['name']},indent=2))
print('Fresh target NAS backup Completed:',b['metadata']['name'])
PY
# All target engine checks passed. Stop the old DB before changing its claim.
"${k[@]}" -n "$ns" scale statefulset zabbix-postgresql --replicas=0
"${k[@]}" -n "$ns" wait --for=delete pod/zabbix-postgresql-0 --timeout=55s
"${k[@]}" -n "$ns" delete pod "$helper"
cutover=1
python3 - "$root" "$here" <<'PY'
import pathlib,json,sys
root,here=map(pathlib.Path,sys.argv[1:]);files=json.loads((here/'prepared-fleet-files.json').read_text())
for name,text in files.items():
 if name.endswith('values.yaml'):
  for field in ('zabbixServer','zabbixWeb','zabbixWebService'):text=text.replace(field+':\n  replicaCount: 1',field+':\n  replicaCount: 0')
 (root/name).write_text(text)
PY
cd "$root"
"$here/../pilot-2026-10-24/apply-bundle.sh" zabbix rancher/fleet/apps/zabbix
arrived=0
for ((attempt=0;attempt<90;attempt++)); do
 if "${k[@]}" -n "$ns" get sts zabbix-postgresql -o json | jq -e --arg target "$target" '.spec.replicas==1 and any(.spec.template.spec.volumes[];.persistentVolumeClaim.claimName==$target)' >/dev/null; then arrived=1; break; fi
 sleep 2
done
[ "$arrived" -eq 1 ] || { echo 'Target PostgreSQL claim not installed' >&2; exit 1; }
ready=0
for ((attempt=0;attempt<10;attempt++)); do
 if "${k[@]}" -n "$ns" rollout status statefulset/zabbix-postgresql --timeout=55s; then ready=1; break; fi
done
[ "$ready" -eq 1 ] || exit 1
"${k[@]}" -n "$ns" get pod zabbix-postgresql-0 -o json | jq -e --arg target "$target" 'any(.spec.volumes[];.persistentVolumeClaim.claimName==$target)' >/dev/null
sql_ready=0
for ((attempt=0;attempt<60;attempt++)); do
 if psql_source 'SELECT 1;' >/dev/null 2>&1; then sql_ready=1; break; fi
 sleep 2
done
[ "$sql_ready" -eq 1 ] || { echo 'Target PostgreSQL SQL not ready' >&2; exit 1; }
psql_source "SELECT 'system_identifier='||system_identifier FROM pg_control_system(); SELECT 'schema='||mandatory||':'||optional FROM dbversion; SELECT 'recovery='||pg_is_in_recovery(); SELECT 'public_tables='||count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p');" > "$backup/database-production-target.txt"
diff -u "$backup/database-baseline.txt" "$backup/database-production-target.txt"
python3 - "$root" "$here" <<'PY'
import pathlib,json,sys
root,here=map(pathlib.Path,sys.argv[1:]);files=json.loads((here/'prepared-fleet-files.json').read_text())
for name,text in files.items():(root/name).write_text(text)
PY
"$here/../pilot-2026-10-24/apply-bundle.sh" zabbix rancher/fleet/apps/zabbix
for client in "${clients[@]}"; do
 for ((attempt=0;attempt<90;attempt++)); do
  [ "$("${k[@]}" -n "$ns" get deployment "$client" -o jsonpath='{.spec.replicas}')" = 1 ] && break
  sleep 2
 done
 "${k[@]}" -n "$ns" rollout status "deployment/$client" --timeout=55s
done
"${k[@]}" -n "$ns" patch cronjob zabbix-nodesclean --type=merge -p "{\"spec\":{\"suspend\":$original_suspend}}"
echo 'Zabbix database migrated and checked; all original writers resumed; source retained'
