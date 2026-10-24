# Second batch results — 2026-10-24

Completed migration of **ddclient, DuckDNS and FlareSolverr** as singleton
Longhorn RWO apps. User explicitly authorized RWO where shared-writer RWX was
not established as safe. This does not approve active-active DNS updaters or
shared Chromium profiles. No other apps were migrated in this batch.

## Storage and rollback

Three 256Mi PVCs use the existing `longhorn-rwo-2replicas` class, with two
healthy running replicas on distinct hosts (proxmox2-old and proxmox3). This adds
**0.75Gi per host / 1.5Gi aggregate nominal replica capacity**. Together with
the first pilot, migrated app requests total 1.75Gi per host. No disks were
resized and the ordinary one-replica `longhorn` class was left unchanged.

| App | Retained source | New target | Volume | Completed native backup |
| --- | --- | --- | --- | --- |
| `ddclient` | `ddclient-config` | `ddclient-config-longhorn-rwo` | `pvc-249d5176-c133-4186-90a5-932f9fcd0df2` | `backup-2909cb560ae54d59` |
| `duckdns` | `duckdns-config` | `duckdns-config-longhorn-rwo` | `pvc-f933cd5e-fdc7-47a5-ba8a-ffe122010aa7` | `backup-81f097b0651c4ebb` |
| `flaresolverr` | `flaresolverr-config` | `flaresolverr-config-longhorn-rwo` | `pvc-e6dc3602-cf29-4734-b69d-ab09d3f325e9` | `backup-2f1649a855cc4145` |

Native backup job `longhorn-system/dns-proxy-nas-backup-20261024` completed.
Each new volume is enrolled in the existing `nas-backup` recurring-job group,
using the same NAS backup target and retention as the first pilot. The native
schedule also processes its other enrolled volumes. No separate restore drill
was run for this batch; the first pilot's isolated native restore already passed.

All source PVCs remain Bound, carry `helm.sh/resource-policy=keep`, and their
PVs have Retain reclaim policy. Production uses only the new claims. No source
PVC, source directory, source PV, or target was deleted. See [README.md](README.md)
for coordinated rollback. Preserve post-cutover config edits before reverting.

## Data and application verification

- ddclient: 9,682-byte config file copied with SHA256 verification while stopped.
  Target ownership/mode remained `568:568`, `0600`; active config contains 11
  non-comment lines. Config contents/credentials were not printed or committed.
  The supervised updater and cron services report up; startup logs include a
  successful DNS-provider IPv4 update. Runtime cache remains outside `/config`.
- DuckDNS: 61-byte `logrotate.conf` copied and SHA256 verified while stopped.
  Its existing values Secret and environment settings were preserved. Cron
  service is up and the user's crontab includes `/app/duck.sh`. `LOG_FILE=false`
  continues to discard updater output, so this task did not claim a newly
  observed successful provider response or force an extra DNS update.
- FlareSolverr: source and target verified to contain no regular config files.
  Singleton Deployment Ready; internal `sessions.list` API returned `ok` and
  zero sessions after restart. This restart clears process-local sessions.
  Both configured **HTTP** ingress hosts returned 200. HTTPS returns 404 under
  the existing HTTP-only Traefik entrypoint configuration (`web`, forceTLS=false);
  ingress settings were not changed as part of storage migration.
- All three Deployments have one available replica, Recreate strategy, and the
  expected new claim mounted. All three app Fleet bundles and the new storage
  bundle reached Ready. Existing helper/StorageClass dependencies remain intact.
- Each target volume is healthy with two running replicas on separate nodes;
  backup-group labels propagated to Longhorn volumes. Source claims remain
  available for a cutover-time rollback.

## Migration timing/recovery behavior

The first ddclient attempt hit the 55-second wait before the configured
60-second graceful shutdown had finished. The pre-cutover failure handler
restored its original instance without copying. The helper was changed to use
up to three bounded shutdown waits; the retry copied only after the old pod
was gone and completed normally.

FlareSolverr initially exceeded its first readiness wait during normal RWO
volume detachment/reattachment to the new node. No force-detach was used; the
pod subsequently became Ready and its API checks passed. The helper now allows
additional bounded rollout waits instead of treating that first short wait as
proof of a failed migration. Failures before cutover restart the original
instance; failures after cutover require inspection and never blindly replace
live data.

## Remaining follow-up

Monitor actual filesystem growth, replicas and scheduled backups. These nearly
empty PVCs remain potential candidates for future persistence removal; this task
preserved their existing mount paths as explicitly requested. No RWX conversion,
extra application replicas, online expansion test or hard-node-failure drill
was performed. Nothing committed or pushed by this operation.
