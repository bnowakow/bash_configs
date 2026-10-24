# OpenBooks and Ubooquity RWO migration — 2026-10-24

User approved migrating both apps after the singleton-RWO batch. Keep one
instance per application, Recreate strategy, original secrets/settings and
unchanged ingress. Ubooquity's embedded database remains single-owner; its
migration does not imply SQLite or shared-writer RWX compatibility.

| App | Retained original PVC | New PVC | New request |
| --- | --- | --- | --- |
| OpenBooks | openbooks-books | openbooks-books-longhorn-rwo | 1Gi |
| OpenBooks | openbooks-logs | openbooks-logs-longhorn-rwo | 256Mi |
| Ubooquity | ubooquity-config | ubooquity-config-longhorn-rwo | 256Mi |

Targets use `longhorn-rwo-2replicas`, Retain/keep, and the existing `nas-backup`
group. Fleet bundle `longhorn-books-storage` owns the three targets and depends
on the first pilot storage bundle for its StorageClass. Added nominal capacity
is 1.5Gi per host, 3Gi aggregate for two replicas. No disks need resizing.

Preflight measured source directories read-only on their owning node: OpenBooks
books empty; logs ~0.053Mi allocated / 0.115Mi apparent; Ubooquity config
~4.792Mi allocated / 4.692Mi apparent. OpenBooks has no shell, so measurements
were made through the PV mapping on the host rather than installing tooling in
its running container. No CloudCasa helper/data-mover pods were active.

## Procedure

Render the pinned charts and validate target claims, singleton settings and
unchanged Ubooquity NFS books mount. Save original workload/repository files
outside Git. Apply storage through Fleet, wait for Ready/Bound, then run
`migrate-one.sh openbooks` and validate before `migrate-one.sh ubooquity`.

The helper protects original claims/PVs, stops the app and waits until its old
pod is gone. Up to three bounded waits accommodate graceful shutdown. A copy
Job mounts sources read-only, preserves metadata and verifies all regular files
by SHA256; empty books are explicitly verified too. Ubooquity is stopped during
its database/config copy. The helper applies app changes through Fleet with
existing GitRepo labels/values, then requires ALL target mounts before checking
rollout. A pre-cutover failure restores original replicas; post-cutover failure
requires inspection, not automatic overwrite of live state.

Verify Fleet readiness, application endpoints, Ubooquity admin path and existing
NAS access, two healthy replicas on separate hosts, and successful NAS backup
for every target. Preserve original PVCs/PVs for rollback.

## Rollback

Stop the affected app and wait for all writers to exit. Restore original Fleet
config-persistence settings and apply through Fleet: OpenBooks originally used
chart-created local-path `openbooks-books` and `openbooks-logs`; Ubooquity used
`ubooquity-config`. The original definitions and deployment records are saved
in `/tmp/longhorn-batch3-originals` during this session. Restore old mounts and
verify app behavior before resuming normal operations. Account for any new
books, logs or library changes since cutover rather than silently discarding
them. Do not delete source or target data as an automatic rollback step.

This migration retains OpenBooks downloads/logs on PVCs as requested. A future
move of downloads to NAS or a log-retention redesign is a separate task.
