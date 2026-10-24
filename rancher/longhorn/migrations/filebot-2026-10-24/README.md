# Disabled Filebot storage migration — 2026-10-24

Scope: migrate retained Filebot config, output and watch claims to Longhorn RWO,
without enabling Filebot or its disabled output/watch mounts. User explicitly
requested migration of this disabled app. No active-active or RWX claim is made.

| Retained source | Target | Request | Application use |
| --- | --- | --- | --- |
| filebot-config | filebot-config-longhorn-rwo | 256Mi | Config mount in the zero-replica Deployment |
| filebot-output | filebot-output-longhorn-rwo | 256Mi | Remains disabled; reference prepared for later review |
| filebot-watch | filebot-watch-longhorn-rwo | 256Mi | Remains disabled; reference prepared for later review |

All targets use the existing `longhorn-rwo-2replicas` class, keep/Retain protection
and `nas-backup` group. The Fleet bundle `longhorn-filebot-storage` owns them and
depends on the original pilot storage bundle. Additional nominal capacity is
0.75Gi per host, 1.5Gi aggregate. Across all completed migrations the application
requests now total 4Gi per host. No disk enlargement is needed.

Preflight confirmed replicas=0, no active Filebot source-volume consumers, and no
active CloudCasa helper/data mover. Measured config used 6.619Mi allocated /
7.414Mi apparent; output/watch were empty. Measurements were read-only through
PV/node mappings. Original private configuration contents were never printed.

## Procedure

1. Save original values, workload/PVC metadata and measurements outside Git.
   Render the pinned chart: config must use the new claim; replicas must stay 0;
   output/watch must not appear as active mounts; `/storage` NAS stays unchanged.
2. Apply storage through Fleet; wait for Ready/Bound. `migrate.sh` verifies the
   app is disabled and no source-volume pod remains active, protects source
   PVCs/PVs, runs `copy-job.json` and checks SHA256 for every regular file.
   Empty output/watch trees are explicitly verified too.
3. Apply the app bundle with the existing Fleet-native helper. Verify target
   config and zero replicas. No app process is started for this migration.
4. Start temporary `backup-holder.json`, mounting all three targets read-only,
   so their two-replica health/placement and native backups can be verified.
   This helper is not Filebot and never writes application files.
5. Trigger the existing native NAS backup job, verify all three target backups,
   and remove the temporary helper. Keep originals and migration evidence.

## Important backup behavior while disabled

The cluster's native recurring backup policy skips detached volumes. Once the
helper is removed these volumes normally detach, because Filebot remains at
zero replicas and output/watch are disabled. The completed migration backups
remain on NAS; enrollment does not mean fresh nightly backups will run for idle
detached volumes. No production data can change on those unused mounts.

Before later activation, verify replicas, config/license usability, NAS access,
application health and backup coverage. Review output/watch capacity before
turning them on: 256Mi is for preserving the currently empty claims, not a bulk
media processing budget. Keeping those mounts disabled is intentional.

## Rollback

Keep Filebot at zero replicas. Restore its original Fleet persistence settings
(config default claim, output/watch disabled) and apply through Fleet. Verify
`filebot-config` is referenced before enabling anything. The old data remains
on all three retained claims. Original definitions are in
`/tmp/longhorn-filebot-originals` during this session. Do not blindly overwrite
post-migration data if Filebot is enabled and used later. Do not delete original
or target data as an automatic rollback step.
