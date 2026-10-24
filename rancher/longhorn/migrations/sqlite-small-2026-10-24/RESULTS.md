# Small SQLite migration results — 2026-10-24

Completed and applied through Fleet: Jellyseerr, Cleanuparr and Uptime Kuma.
Each has one running application replica, Recreate strategy, and a 256Mi RWO
claim on `longhorn-rwo-2replicas`. Every target has two healthy storage replicas,
one on proxmox2-old and one on proxmox3. All four changed Fleet bundles report
1/1 BundleDeployments ready, including `longhorn-sqlite-small-storage`.

| App | New claim | Fresh apparent source size | Files SHA256 verified | SQLite quick checks |
| --- | --- | ---: | ---: | --- |
| Jellyseerr | jellyseerr-config-longhorn-rwo | 11.44Mi | 39 | db/db.sqlite3: OK |
| Cleanuparr | cleanuparr-config-longhorn-rwo | 9.97Mi | 67 | cleanuparr.db, users.db, events.db: all OK |
| Uptime Kuma | uptime-kuma-config-longhorn-rwo | 15.75Mi | 3 | kuma.db: OK |

The applications were stopped and their old pods gone before the full trees
(including WAL/SHM files) were copied. Every regular file matched its source
SHA256 before checking SQLite on the writable target with read-only connections.
No source database checkpoint or repair was performed. Original local-path
claims remain Bound with Helm keep annotations; source PVs use Retain.
Do not run the retained source copies alongside the migrated writers.

## Runtime validation

- All three Deployments have one available replica and reference the new claim.
- Both configured HTTPS ingress suffixes for each app returned HTTP 200 with
  normal certificate verification (six checks).
- Jellyseerr `/api/v1/status`, Cleanuparr `/cleanuparr/health/ready`, and Kuma
  `/socket.io/?EIO=4&transport=polling` returned HTTP 200 (three checks).
- Recent application logs showed no SQLite corruption, malformed database,
  locked database or read-only database errors in the inspected 150-line windows.
- Authenticated workflows, forced Cleanuparr cleanup and synthetic Kuma
  notifications were not exercised. Single-instance ownership remains required.

Jellyseerr's rollout waited for its existing image to download on the other
node. The unchanged Cleanuparr/Kuma images were then cached on both nodes.
Kuma was allowed its full graceful shutdown before copying. Cleanuparr's chart
omits Deployment replicas: the helper restored one replica only after the new
claim reference was present. Chart/image versions and application settings
were preserved.

## Backups and restore

Native backup Job `longhorn-system/sqlite-small-nas-backup-20261024` completed
at **2026-10-24 18:26:44 UTC**. All three NAS backups report Completed:

| App | Volume | Backup |
| --- | --- | --- |
| Jellyseerr | pvc-8954c7e8-8cd5-40b1-aeff-1d7f0879fcb3 | backup-76e42a945e0d4fc9 |
| Cleanuparr | pvc-6267e84f-fa40-47ed-a7ef-d8060a992c63 | backup-e2e9475574014206 |
| Uptime Kuma | pvc-326def38-faba-49f6-8a78-ebf719227220 | backup-3101d83e8b424afa |

Jellyseerr's backup was restored to a separate temporary 256Mi RWO volume.
An isolated Python Job opened the restored `db/db.sqlite3` and passed SQLite
`PRAGMA quick_check`. No production mount or application process was used in
that test. The temporary restore Job, PVC and Delete-policy StorageClass were
removed afterward, along with preflight/image-cache Jobs. Migration copy Jobs
remain as execution evidence. This validates one representative SQLite restore;
Cleanuparr and Kuma were backed up but not separately restore-tested.

All targets join the existing daily `nas-backup` group (14 retained backups).
The backups are live volume snapshots; SQLite/WAL recovery was checked for the
representative restored Jellyseerr database, rather than assuming every future
live snapshot is application-quiesced.

## Capacity and records

This batch adds 768Mi requested capacity, nominally 768Mi per node / 1.5Gi
aggregate with two replicas. All migrated production apps now total **12 apps,
16 RWO claims, 4.75Gi requested**, nominally 9.5Gi aggregate replicas. Remaining
nominal node budgets after removing the restore scratch volume are approximately
**65.61Gi** on proxmox2-old and **93.10Gi** on proxmox3. Physical allocation,
snapshots and free-space margins are separate. No disks were enlarged.

The [current storage summary](../../current-app-storage-summary-2026-10-24.md),
[assessment](../../fleet-storage-migration-assessment-2026-10-24.md) and measured
CSV now mark these apps completed. Remaining conservative proposals total
71.25Gi; historical source measurements are retained and need refreshing before
future migrations. No other app was migrated and no Git commit/push was made.

Helper validation included Bash syntax and ShellCheck, a healthy SQLite/WAL
fixture, rejection of a corrupt SQLite fixture, and a mocked failed-copy path
that restored the old replica count without applying the target cutover.
See [procedure and rollback](README.md) for the retained-source rollback steps.
