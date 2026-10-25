# Zabbix PostgreSQL migration — 2026-10-25

Approved target: 18Gi RWO `apps-zabbix/zabbix-postgresql-data-longhorn-rwo`,
`longhorn-rwo-2replicas`, two storage replicas, daily NAS group, keep/Retain.
Original local claim `postgresql-data-zabbix-postgresql-0` is retained. Its PV is
named `nas-zabbix-postgresql-data` but its actual backend is local-path at
`/var/lib/rancher/k3s/storage/migrated-from-nas/zabbix-postgresql`.

## Controlled transfer instead of bulk filesystem copy

Because prior bulk copies coincided with etcd/API outages, this uses PostgreSQL's
native backup protocol at **4MiB/s**, with a **spread checkpoint**. Zabbix server,
web and webservice writers are stopped; nodesclean CronJob is suspended.
Unexpected remaining SQL clients block the backup. PostgreSQL stays running to
serve a consistent entire-cluster physical backup, preserving roles/credentials,
all databases, schema, indexes and history. No repair/reindex or SQL migration.

The source is PostgreSQL **16.15**, data checksums off, database ~6920MB at
preflight, no extra tablespaces or unlogged tables. The exact source image digest
is used by the helper and pinned in the final chart values, avoiding an incidental
change from mutable `postgres:16`. Zabbix images/chart versions stay unchanged.

A source-local trusted Unix connection avoids editing authentication or passing
passwords. A **temporary** physical replication slot reserves WAL for fetch mode
in a tagged psql session bounded to two hours. The native archive includes needed
WAL. The slot session is terminated/dropped after transfer or on failure.
No persistent PostgreSQL authentication/configuration changes are required.

The binary tar stream goes directly through two kubectl exec streams to the
isolated target helper; no database contents are printed or stored in the repo.
It is extracted with original ownership/modes and the target filesystem synced.
`pg_verifybackup` verifies the SHA256 manifest and recovery WAL with the exact
PostgreSQL version. The target is then started/stopped in isolation with only a
private Unix socket, confirming cluster identifier, Zabbix DB schema version,
recovery state and public-table count against the stopped-writer baseline.

The initial backup manifest is archived privately under
`/tmp/longhorn-zabbix-originals`, then removed from the live data directory so it
isn't mistaken for a manifest of later live writes. A native NAS backup is taken
while the checked target PostgreSQL is stopped and the helper holds it attached.
A second large native-snapshot restore is not part of this run: the PostgreSQL
native backup restore/recovery is tested before cutover, and the original local
cluster is retained. Record that limitation explicitly in RESULTS.md.

## Cutover and rollback

Only after verification and a fresh Completed NAS backup is source PostgreSQL
stopped. The chart is staged on the target claim with all app writers still zero.
Require actual pod target mount plus successful SQL/identity/schema checks, then
restore the original writer replica counts and CronJob suspend state. Verify
Fleet, all workloads, HTTPS, database operation, Secret data and replica health.

Pre-cutover failure terminates the slot guard and restores original PostgreSQL/
writer replicas. Post-cutover failures require inspection, not a blind return to
stale source data. To roll back intentionally, stop all target writers, restore
the original claim references via Fleet and reconcile any changes since cutover
before starting exactly one database. Never expose both DB copies as backends.

Prepared target definitions are activated by migrate.sh only after all checks.
Original definitions/metadata are under `/tmp/longhorn-zabbix-originals`.
See RESULTS.md for executed outcomes and backup IDs. Mailpile remains last and
its old failed staging allocation is unrelated to this migration.

Primary references: [pg_basebackup](https://www.postgresql.org/docs/16/app-pgbasebackup.html),
[pg_verifybackup](https://www.postgresql.org/docs/16/app-pgverifybackup.html).
