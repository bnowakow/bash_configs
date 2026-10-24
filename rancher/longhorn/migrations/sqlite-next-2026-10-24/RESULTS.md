# Bindery, Bazarr and Authelia migration results — 2026-10-24

Completed and applied through Fleet. Each app uses a 256Mi RWO claim on
`longhorn-rwo-2replicas`, two healthy storage replicas on separate hosts,
one running application replica and Recreate deployment strategy. All four
changed Fleet bundles report 1/1 BundleDeployments ready.

| App | New claim | Fresh apparent source size | Files SHA256 verified | SQLite check |
| --- | --- | ---: | ---: | --- |
| Bindery | bindery-config-longhorn-rwo | 25.16MiB | 191 | bindery.db: OK |
| Bazarr | bazarr-config-longhorn-rwo | 69.24MiB | 45 | db/bazarr.db: OK |
| Authelia | authelia-config-longhorn-rwo | 0.36MiB | 3 | db.sqlite3: OK |

The old application pod was gone before copying each complete data tree,
including WAL/SHM files. SHA256 matched every regular source file before SQLite
`PRAGMA quick_check` on the target. Source mounts were read-only. Original
local-path PVCs remain Bound with Helm keep annotations, and their PVs use
Retain. These source copies are rollback state, not additional active apps.

## Application and Fleet validation

- All three apps have one available replica and reference the new claim.
- Target volumes are healthy, with a running replica on proxmox2-old and proxmox3.
- Both HTTPS suffixes passed certificate-verified HTTP 200 checks for each app:
  Bindery `/api/v1/health`, Bazarr `/`, Authelia `/api/health` (six checks).
- Recent 150-line log windows contain no SQLite corruption/locked/read-only
  database messages or permission-denied errors.
- Authelia's live container environment matches its original configuration,
  including existing encryption, session and JWT secret references. User data
  files matched the original source; the seed init container does not overwrite
  an existing user database.
- Authenticated login/2FA, actual subtitle downloads and Bindery imports were
  not exercised. Please test those normal user workflows.

Bindery's vendored chart gained an optional existingClaim setting and suppresses
its own PVC when an external claim is selected. Rendering and Helm lint passed;
its default configuration still renders the original chart-owned claim. All
pinned application images/chart versions and media NFS settings were preserved.
Bazarr's first ingress check during rollout returned 503 while its image and
readiness were pending; it subsequently became Ready and returned 200.

One attempted Bindery `/bindery --help` runtime check unexpectedly started a
second process, briefly opened the database and exited on the occupied port.
The primary app stayed healthy. Subsequent checks used HTTP endpoints; recent
primary logs had no database errors. This command must not be reused as a probe.

## NAS backups and restore

Native Job `longhorn-system/sqlite-next-nas-backup-20261024` completed at
**2026-10-24 18:55:44 UTC**. All three new backups report Completed:

| App | Volume | Backup |
| --- | --- | --- |
| bindery | pvc-0562a0af-a5f4-45e8-8cb0-1c326a6bd2a3 | backup-3a7f1c5a2c3b44b2 |
| bazarr | pvc-d39d4b0f-cf1c-4b13-817d-ea392f17afb6 | backup-6904405111774d2d |
| authelia | pvc-8a77b8d0-23e1-45dd-b2d1-35e5c8786353 | backup-084433b810c24204 |

Authelia's backup was restored into an isolated temporary 256Mi RWO volume.
A Python Job opened the restored `db.sqlite3` using a read-only SQLite connection
and `PRAGMA quick_check` returned OK. No production mount or Authelia process
was used in this restore test. The temporary Job/PVC/Delete-policy StorageClass
and measurement Jobs were removed afterward. Copy Jobs remain as evidence.
Bindery and Bazarr backups were not individually restore-tested.

Targets join the existing daily `nas-backup` recurring group, retaining 14
backups. These are live volume snapshots; the successful representative restore
is not a claim that every future snapshot is application-quiesced.

## Capacity and records

This batch adds **0.75Gi per host / 1.5Gi aggregate** nominal replica capacity.
Migrated production apps now total **15 apps, 19 RWO claims and 5.5Gi requested**
(11Gi aggregate replicas). Nominal remaining budgets are approximately
**64.86Gi on proxmox2-old and 92.35Gi on proxmox3**, excluding physical allocation,
snapshot growth and required free-space margins. No disk enlargement or default
StorageClass change was made. Remaining local proposals total 70.5Gi/26 claims.

Updated the [current storage summary](../../current-app-storage-summary-2026-10-24.md),
[assessment](../../fleet-storage-migration-assessment-2026-10-24.md) and original
measured CSV completion markers. Historical measurements remain historical.
Bash syntax, ShellCheck, Helm rendering/lint and git diff whitespace checks pass.
The copy/check implementation is reused from the preceding tested batch.
No commit or push was made. See [procedure and rollback](README.md).
