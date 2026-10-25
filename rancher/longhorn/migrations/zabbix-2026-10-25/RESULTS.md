# Zabbix migration results — 2026-10-25

Migrated `apps-zabbix` PostgreSQL to **18Gi RWO**, storage class
`longhorn-rwo-2replicas`, claim `zabbix-postgresql-data-longhorn-rwo`.
Two healthy storage replicas are on separate hosts. PostgreSQL and all three
Zabbix deployments have one application/database replica; RWX is not enabled.
Zabbix remains **ubuntu-7.4.16**, chart **7.1.0**. PostgreSQL remains **16.15**,
pinned to the exact source digest rather than the mutable `postgres:16` tag.

## Data preservation and recovery checks

Stopped Zabbix server/web/webservice and suspended `zabbix-nodesclean` before
copying. No unexpected SQL clients remained. Source PostgreSQL stayed running
to serve a native physical backup with a spread checkpoint, SHA256 manifest
and fetched recovery WAL, throttled to **4MiB/s**. A temporary physical
replication slot retained WAL and was removed after transfer. No authentication,
password or persistent database settings were changed.

`pg_verifybackup` passed its manifest/file/WAL checks. The extracted PostgreSQL
cluster started and stopped cleanly in isolation, with matching source values:

- System identifier: `7460106167972982823`.
- Zabbix dbversion mandatory `7040000`, optional `7040011`.
- Public table count: `207`; recovery state: `false`.

The production target passed the same identity/schema/table checks before
writers resumed. A fresh native NAS backup completed with PostgreSQL stopped
on the checked target. Backup identifier and volume are recorded below.

The native PostgreSQL backup's restore/recovery was tested. **The native NAS
snapshot was not separately restored** in this run, to avoid another large
uncontrolled restore after earlier I/O/control-plane outages. Original local
source data remains available for deliberate rollback. No control-plane repair
is claimed; k3s restart count remained unchanged at 15 during the controlled
transfer and final checks.

## Runtime validation

Fleet app and storage bundles were Ready; PostgreSQL mounted the new claim,
and server/web/webservice rollouts completed. Normal SQL operation, original
Opaque Secret data, two healthy replicas on distinct nodes and both
certificate-verified HTTPS endpoints were checked. `zabbix-nodesclean` was
restored to its original unsuspended state. PostgreSQL logged one transient `database system is starting up` connection
rejection during startup; it then became ready, with no matching storage/auth
errors in the inspected server/web logs. No temporary replication slots or
transfer helper remained. Interactive authenticated monitoring workflows still
require user testing; no synthetic alerts or configuration changes were sent.

## Retained source and capacity

Original claim `postgresql-data-zabbix-postgresql-0` remains Bound and marked
keep; PV `nas-zabbix-postgresql-data` remains Retain. Despite its name, its
backend is local `/var/lib/rancher/k3s/storage/migrated-from-nas/zabbix-postgresql`.
The source is a stale rollback copy after writers resume; stop target writers
and reconcile changes before any intentional rollback. Do not activate two
copies as database backends.

Production migration totals: **27 apps, 37 RWO claims, 36.75Gi requested**
(73.5Gi nominal aggregate replicas). Mailpile stays local and **last by user
instruction**; its separate 9.25Gi staging allocation is still unverified.
See [current inventory](../../current-app-storage-summary-2026-10-24.md) and
[remaining priority](../../remaining-migration-priority-2026-10-24.md).

## NAS backup record

- Backup: `backup-f8d721b7de6048ce`, Completed, 100%, no error.
- Created: `2026-10-25T11:52:48Z`.
- Volume: `pvc-885c02ea-0331-4c7e-9408-e07f7ac6ec70`.
- Job: `longhorn-system/zabbix-nas-backup-20261025`, Complete.
- Cutover and workload checks completed by `11:59 UTC` (12:59 CET).
