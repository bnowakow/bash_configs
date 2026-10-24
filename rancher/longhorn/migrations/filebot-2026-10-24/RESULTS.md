# Filebot storage migration results — 2026-10-24

Migrated Filebot's three retained PVCs to Longhorn RWO. **Filebot remains
scaled to zero. Output/watch mounts remain disabled.** No Filebot process was
started, no license activation attempted, and no media files were processed.

## Claims and initial backups

All new claims request 256Mi, use `longhorn-rwo-2replicas`, retain/keep protection
and the `nas-backup` recurring-job group. While attached for verification, each
volume was healthy with two running replicas, one on each Longhorn node.

| Retained original | New PVC | Completed NAS backup |
| --- | --- | --- |
| `filebot-config` | `filebot-config-longhorn-rwo` | `backup-d82ef9d57caa48bb` |
| `filebot-output` | `filebot-output-longhorn-rwo` | `backup-db2a403f0e88436f` |
| `filebot-watch` | `filebot-watch-longhorn-rwo` | `backup-f27af10560ab4252` |

Added nominal capacity: **0.75Gi per host / 1.5Gi aggregate replica capacity**.
Across all completed app migrations: **4Gi per host**. No disk size or default
StorageClass was changed. The Fleet storage bundle is `longhorn-filebot-storage`.

## Verification

- Preflight confirmed Filebot replicas=0 and no active pods consuming source
  PVCs. No CloudCasa helper/data-mover pods were active.
- Fresh source measurements: config 6.619Mi allocated / 7.414Mi apparent;
  output/watch empty. Private config/license contents were not printed.
- Copy Job `apps-filebot/filebot-longhorn-20261024` completed all three
  containers. Every regular config file passed SHA256 verification; empty
  output/watch trees were explicitly checked. Sources were mounted read-only.
- The rendered chart has replicas=0, uses `filebot-config-longhorn-rwo`, renders
  no chart-owned PVC, and excludes disabled output/watch mounts. Their new
  references are retained in values for later deliberate activation/review.
- `/storage` remains NFS from
  `nas.localdomain.bnowakowski.pl:/mnt/PlexPool/plex`; ingress/image/pinned chart
  version remain unchanged. No runtime NAS/UI test was possible without
  enabling the application, which was intentionally not done.
- Fleet bundles `filebot` and `longhorn-filebot-storage` reached Ready.
  Filebot's zero desired replicas are intentional, not a failed rollout.
- Temporary `filebot-backup-holder-20261024` mounted all targets read-only for
  replica verification and backup. Native job
  `longhorn-system/filebot-nas-backup-20261024` completed, with a Completed
  backup for each target. No additional restore drill was performed.
- Original source PVCs remain Bound with keep annotations; all source PVs have
  Retain. No original data directories, PVCs or PVs were removed.

## Disabled-volume backup behavior

The live `allow-recurring-job-while-volume-detached` setting is **false**.
The temporary helper was removed and all three new volumes were confirmed detached;
`robustness: unknown` on a detached volume is not a failed active replica check.
Two-replica health and placement were verified while attached, before cleanup.
The initial NAS recovery points above persist, but detached volumes are skipped
by recurring backups under the existing policy. No unused-volume data changes
are expected while the app and mounts remain disabled. Before enabling Filebot,
recheck replica health, backup coverage and license/config usability.

Output/watch requests are only 256Mi because both sources were empty and remain
disabled. Review capacity or NAS-backed destinations before enabling them for
large media processing. Config growth and log retention also need monitoring.

## Rollback / status

See [README.md](README.md) for original claim names and coordinated rollback.
Keep Filebot stopped while switching references. Private original definitions
are saved in `/tmp/longhorn-filebot-originals` during this session; do not commit
application configuration or licenses. Reconcile any later writes before
returning to cutover-time data. No hard-node-failure or expansion test was run.
Nothing committed or pushed by this migration.
