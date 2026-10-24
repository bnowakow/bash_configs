# Audiobookshelf, Scrutiny and Prowlarr migration results — 2026-10-24

Completed and applied via Fleet. All three apps have one available replica,
Recreate strategy and their new RWO mounts. All five volumes use
`longhorn-rwo-2replicas`, with two healthy replicas on distinct nodes
(proxmox2-old/proxmox3). The three app bundles and new storage bundle each report
1/1 BundleDeployments ready. Original PVCs remain Bound with Helm keep; their
source PVs use Retain. No source or production data volume was deleted.

| App | New claim | Request | Files SHA256 checked | SQLite quick_check |
| --- | --- | ---: | ---: | --- |
| Audiobookshelf | audiobookshelf-config-longhorn-rwo | 256Mi | 16 | absdatabase.sqlite: OK |
| Audiobookshelf | audiobookshelf-metadata-longhorn-rwo | 1Gi | 58 | Metadata copied, including backup files |
| Scrutiny | scrutiny-config-longhorn-rwo | 256Mi | 1 | scrutiny.db: OK |
| Scrutiny | scrutiny-influxdb-longhorn-rwo | 1Gi | 485 | influxd.sqlite: OK |
| Prowlarr | prowlarr-config-longhorn-rwo | 256Mi | 912 | prowlarr.db + logs.db: OK |

Fresh read-only source measurements before stopping:

| Claim | Allocated bytes | Apparent bytes |
| --- | ---: | ---: |
| Audiobookshelf config | 377344 | 1732363 |
| Audiobookshelf metadata | 2034176 | 18124596 |
| Scrutiny config | 4608 | 40960 |
| Scrutiny InfluxDB | 2299904 | 168657967 |
| Prowlarr config | 49790464 | 171580646 |

The entire app was stopped and old pod gone before each copy. Full trees,
including WAL/SHM files, were copied with metadata preserved and all regular
files checksummed before checking SQLite on target mounts. Source mounts stayed
read-only. A local multi-claim SQLite/WAL fixture also passed and its source
bytes stayed unchanged. No active CloudCasa helper/kubemover was present.

## Runtime and engine validation

- Six certificate-verified HTTPS checks returned 200: both configured suffixes
  for Audiobookshelf `/ping`, Scrutiny `/api/health` and Prowlarr `/ping`.
- All five target claim references are installed and all three Deployments have
  exactly one desired/available replica. App images and chart versions are
  unchanged; Audiobookshelf NFS media trees are unchanged.
- Scrutiny remains on its original **proxmox3** host using an explicit
  nodeSelector, preserving host `/run/udev`/privileged collector scope.
- Scrutiny's stopped-target InfluxDB verification found **0 broken blocks out
  of 2668**, no corrupt WAL files (one file checked), and passed series-file
  verification. Both SQLite files passed quick_check before cutover.
- Recent 150-line app log windows contain no SQLite corruption, malformed,
  locked/read-only database or permission-denied messages.
- Scrutiny's API summary retains **all three original device records**. Three
  additional `IET VIRTUAL-DISK` SCSI devices appeared after restart, with
  `smartctl` error code 4/checksum warnings. These are virtual-device collector
  errors, distinct from InfluxDB TSM/WAL checks, which passed. Collector discovery
  settings and existing inventory were not altered or deleted by this migration.
  Review/exclude virtual devices separately using the
  [upstream collector configuration](https://github.com/AnalogJ/scrutiny/blob/v0.9.5/example.collector.yaml),
  rather than interpreting these messages as database corruption.

Authenticated app workflows, audiobook playback and real Prowlarr searches were
not exercised. The user should test those normal workflows. Six-device summary
count is not a six-physical-drive assertion; original history/records are retained.

## NAS backups and restored InfluxDB

Native backup Job `longhorn-system/media-small-nas-backup-20261024` completed at
**2026-10-24 19:18:08 UTC**. All five new volume backups report Completed:

| Claim | Longhorn volume | Backup |
| --- | --- | --- |
| audiobookshelf-config-longhorn-rwo | pvc-ebd53b13-0354-4804-b4f1-171e911efdf2 | backup-5929268569a24793 |
| audiobookshelf-metadata-longhorn-rwo | pvc-b3ebfaf2-91bf-4471-8dae-f11479196847 | backup-41260eaaadfd4aba |
| scrutiny-config-longhorn-rwo | pvc-1e18638c-c18a-465c-8f0b-93d41b2317b2 | backup-235e3cf393bc4562 |
| scrutiny-influxdb-longhorn-rwo | pvc-f21e0793-9490-4617-b8e0-89da3840d819 | backup-66465ced27ba46b7 |
| prowlarr-config-longhorn-rwo | pvc-66073c5a-38e7-4aa1-944e-5cd8446f13b9 | backup-a15c20de29e84661 |

Both Scrutiny backups were restored into isolated temporary RWO volumes (256Mi
config and 1Gi InfluxDB). Its two restored SQLite databases passed quick_check.
The pinned InfluxDB binary passed TSM/WAL/series-file checks again (0/2668 broken
blocks; no corrupt WAL files, including eight replayable WAL entries), then
started against the restored Bolt/SQLite/engine paths. `/health` reported pass
and `/api/v2/setup` reported setup disallowed, confirming initialized metadata
loaded. The test bound only localhost and ran no Scrutiny collector/web server,
exposed service/ingress or Influx task scheduler. It never mounted production
claims. See `check-restored-influx.sh` for the exact engine test.

The restore Job, scratch PVCs/Delete-policy StorageClasses and read-only
measurement Jobs were deleted afterward. Copy Jobs remain as execution evidence.
Audiobookshelf and Prowlarr backups were not separately restore-tested.
All targets join the existing daily `nas-backup` group with 14 retained backups.
These are live volume snapshots, not a claim of application-quiesced recurring
backups. Two Scrutiny claims were backed up separately rather than atomically;
this representative pair restored successfully, while future cross-volume
consistency still requires application-aware coordination when necessary.

## Capacity and records

This batch added **2.75Gi nominal capacity per host / 5.5Gi aggregate replicas**.
Migrated production apps total **18 apps, 24 RWO claims, 8.25Gi requested**
(16.5Gi nominal aggregate replicas). Remaining proposals total **67.75Gi across
21 source claims**. Nominal remaining budgets after scratch cleanup are about
**62.11Gi on proxmox2-old / 89.60Gi on proxmox3**; physical allocation, snapshots
and free-space thresholds are separate. No disks/default StorageClass changed.

Updated the [app summary](../../current-app-storage-summary-2026-10-24.md),
[assessment](../../fleet-storage-migration-assessment-2026-10-24.md), CSV completion
markers and [remaining size ranks](../../remaining-migration-priority-2026-10-24.md).
Bash/POSIX shell syntax, ShellCheck, render invariants, multi-claim copy/WAL fixture
and whitespace checks passed. No Git commit or push was made.
See [procedure and rollback](README.md).
