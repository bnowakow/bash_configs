# Small SQLite apps to singleton Longhorn RWO — 2026-10-24

Approved scope: Jellyseerr, Cleanuparr, Uptime Kuma. Each keeps one active
application instance and Recreate strategy; no RWX conversion or application HA
is introduced. Each new config PVC is 256Mi on `longhorn-rwo-2replicas`, with
keep/Retain protection and the `nas-backup` recurring-job group.

| App | Retained original | Target | Original mount |
| --- | --- | --- | --- |
| Jellyseerr | jellyseerr-config | jellyseerr-config-longhorn-rwo | /app/config |
| Cleanuparr | cleanuparr-config | cleanuparr-config-longhorn-rwo | /config |
| Uptime Kuma | uptime-kuma-config | uptime-kuma-config-longhorn-rwo | /app/data |

Fresh source apparent sizes: Jellyseerr 11.44Mi, Cleanuparr 9.97Mi, Kuma 15.75Mi.
Preflight found no active CloudCasa helper/data mover. Both source nodes passed
Python/SQLite tooling checks before any app was stopped. Images/chart versions,
secrets, ingress and application settings are preserved.

Added nominal capacity: 0.75Gi per host / 1.5Gi aggregate with two replicas.
Total migrated application PVC requests after this batch: 4.75Gi per host.
No disk enlargement or default StorageClass change is required.

## Execution and checks

1. Save original workload/PVC/repository metadata outside Git, render pinned
   charts and verify no chart-owned PVC is rendered for the external targets.
   Apply `longhorn-sqlite-small-storage` through Fleet and wait for Ready/Bound.
2. Run `migrate-one.sh APP` one application at a time. It rejects another active
   source-volume consumer, protects source claims/PVs, stops the application
   and waits until the old pod is gone. No target cutover is allowed on timeout.
3. `APP-copy-job.json` embeds `copy-and-check.py`: copy the complete source tree
   with metadata preservation, including any WAL/SHM sidecars; verify SHA256 of
   every regular file; then run SQLite `PRAGMA quick_check` on every SQLite file
   identified by header and filename extension in the writable TARGET mount.
   Original source mounts remain read-only. Read-only SQLite connections may
   need temporary/shared-memory sidecar handling on the target; no source
   checkpoint, database repair or schema change is performed; user table contents
   are not queried or printed.
4. The Job must complete all checks successfully before the app bundle is
   applied through Fleet. Pre-cutover failure restores the original deployment
   replica count. Post-cutover failures require inspection, not blind overwrite.
5. Check target mount, one desired replica, rollout and Fleet readiness, API/
   ingress behavior, two healthy replicas on distinct nodes and NAS backup.
   Keep original claims/PVs for rollback; don't run old and new writers together.

## Cleanuparr chart difference

The pinned 0.20.4 chart uses `deployment.volumes` and `persistentVolumeClaims`,
not TrueCharts `existingClaim`. Its source PVC rendering is disabled with
`persistentVolumeClaims: null`; the new claim is owned by the storage bundle.
The Deployment template omits `spec.replicas`. The helper explicitly restores
one replica ONLY AFTER observing the new target claim in the Deployment; it
must not restart Cleanuparr against its original DB during cutover.

## Rollback

Stop the migrated app and wait for its writer to exit. Restore original Fleet
settings and original claim references above (Cleanuparr's original chart PVC
map must also be restored). Apply through Fleet preserving GitRepo labels and
ensure one replica. Confirm the old mount before testing app behavior.
Original metadata/repository definitions are under
`/tmp/longhorn-sqlite-small-originals` during this session. Data written since
cutover requires an explicit decision before returning to older source state.
Do not blindly copy a running SQLite DB, omit WAL files, or delete either data
copy. Uptime Kuma can resend notifications after restart; keep one scheduler.
Cleanuparr's integrations/settings are copied, not reset or exercised by forcing
cleanup operations. Private config and credentials must not be committed.
