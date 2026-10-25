# Sonarr, youtube-dl Material and AdGuard Home — 2026-10-24/25

Approved batch: Sonarr config 1Gi; youtube-dl Material appdata/users 256Mi each
and MongoDB data 1Gi; AdGuard config 256Mi and data 4Gi. Six RWO claims total
6.75Gi per host / 13.5Gi aggregate with two Longhorn replicas. Original source
claims remain rollback copies, protected with Helm keep/PV Retain.

The initial preflight was blocked by k3s/etcd instability; HANDOFF.md preserves
that history and the separate root investigation. The resumed execution first
verified Ready nodes, etcd/API readiness, a stable restart count and low observed
WAL fsync latency. It did not reset etcd, edit firewall/service settings or claim
to diagnose/fix the original outage. Tool/image preparation completed before
stopping any application.

## Execution

The storage bundle was applied via the Fleet-native pilot apply helper. App
target definitions remain in `prepared-fleet-files.json` until their stopped
copies pass. `migrate-one.sh APP` requires original singleton sources/available
workloads, Bound target claims, no unknown source consumers and no active target
consumers. It saves source metadata under
`/tmp/longhorn-sonarr-ytdl-adguard-originals`, protects originals, stops writers,
waits for their pods to exit, and runs the complete copy/engine check Job.

Every regular file is SHA256 matched, including any WAL/SHM sidecars, with
metadata preserved. Sonarr requires SQLite quick_check success. AdGuard uses
GNU cp `--sparse=always` to preserve/create holes in zero ranges; this does not
guarantee the source filesystem's allocated size on the new filesystem. Source
allocation may also reflect compression. Target logical size and actual
Longhorn node free space are distinct quantities.

If a pre-cutover check fails, the helper restores original replicas; a database
is started before its app. Target references are written/applied only after
checks succeed and no original consumer is alive. A post-cutover failure needs
inspection rather than automatic return to stale source data.

## MongoDB

Stop youtube-dl Material first, MongoDB second. Copy all three state volumes
with neither writer running. `check-mongodb.sh` starts the same pinned MongoDB
9.0.4 binary against the copied target, bound only to localhost, no auth/network
service, a 0.25Gi WiredTiger cache and no repair. It runs full validation on all
collections and requires the application database to exist. It stops cleanly
before Fleet activates target mounts. User records/credentials are not printed.

The checker must use production UID **568** and GID 0. The first attempt used
the image default UID, exited before validation and did not cut over; the helper
restored original writers. The retry clears only the failed derived target
copies, guarded by original live source references/no active target consumers,
then takes a fresh stopped copy. Failed-Job evidence is preserved under /tmp.
Opaque MongoDB/app Secret data is compared before/after to prevent credential
changes. The app is staged at replicas=0 until target MongoDB becomes Ready,
then applied again at replicas=1. Normal app startup can take several minutes
and refresh downloader binaries. NFS media/subscriptions remain external.

## AdGuard and DNS

AdGuard is last. Both hosts' original upstream resolvers are independent public
resolvers; host and in-cluster FQDN probes resolve NAS/registry names before and
while AdGuard is stopped. Tools/images are cached first. AdGuard remains pinned
to its original proxmox3 host for cutover; DNS LoadBalancer services/ports stay
unchanged. No resolver configuration is changed.

A temporary local-path tooling PVC holds the static bbolt 1.4.3 CLI built before
downtime. Target `stats.db` and `sessions.db` must both pass `bbolt check`; no
source database is opened/repaired. This remains single-owner RWO, never shared
concurrent bbolt writers. Validate UDP/TCP DNS through both node IPs and both
HTTPS hosts after startup.

## Backups, validation and rollback

Verify Fleet readiness, every target reference, singleton/Recreate, two healthy
replicas on distinct nodes, HTTPS and DNS. Trigger native NAS backups, record
completed IDs, and restore-test representative MongoDB and AdGuard backups using
isolated scratch volumes with no production mounts or external service. Remove
scratch/tooling resources after success; keep copy Jobs as evidence.

For rollback, stop new writers and wait for pods to exit. Restore original
Fleet definitions/claim references saved outside Git, then apply preserving
GitRepo ownership. For youtube-dl Material restore all three state volumes
consistently and bring MongoDB up before the app. Decide explicitly how to
reconcile writes after cutover before returning to stale sources; never run old
and new database copies as concurrent app backends. See RESULTS.md for evidence.
