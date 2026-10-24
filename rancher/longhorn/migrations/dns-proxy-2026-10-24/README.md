# ddclient, DuckDNS and FlareSolverr — singleton RWO migration

User explicitly approved migrating these three as RWO after the RWX audit.
This is an exception to the earlier ordering restriction, not an assertion that
shared writers or multiple application replicas are safe. Keep one instance per
service, Recreate rollouts, and the original settings/credentials.

The Fleet bundle `longhorn-dns-proxy-storage` provisions three 256Mi claims on
`longhorn-rwo-2replicas` (provided by the first-pilot storage bundle). Each has
Retain/keep protection and belongs to the existing `nas-backup` recurring group.
Additional nominal capacity: 0.75Gi per host with two replicas, 1.5Gi aggregate.
No storage disk enlargement or change to the default StorageClass is required.

| App | Namespace | Source retained claim | Target |
| --- | --- | --- | --- |
| ddclient | apps-ddclient | ddclient-config | ddclient-config-longhorn-rwo |
| DuckDNS | apps-duckdns | duckdns-config | duckdns-config-longhorn-rwo |
| FlareSolverr | apps-flaresolverr | flaresolverr-config | flaresolverr-config-longhorn-rwo |

Preflight: both Longhorn nodes schedulable, existing active volumes healthy;
no CloudCasa helper/data-mover pods active. Fresh contents: ddclient config file
9,682 bytes, DuckDNS logrotate config 61 bytes, FlareSolverr config directory
empty. No database files or configuration secrets were printed. The user chose
to preserve these PVC-backed paths rather than remove persistence in this task.

## Execution

1. Save source workload/PVC definitions and original repository files outside
   Git. Render the pinned charts to check existingClaim and one replica.
2. Apply storage through Fleet with GitRepo labels preserved; wait for all
   targets Bound. Protect old claims with keep and old PVs with Retain.
3. Run `migrate-one.sh APP`, one service at a time. It stops the old pod,
   waits for graceful termination (bounded 55-second waits, up to three),
   and refuses to copy while the old pod remains. Before cutover, failure
   restores the original replica count; after cutover, inspect before rollback.
4. A copy Job mounts the source read-only, preserves file metadata and checks
   SHA256 of every regular file. Empty sources are explicitly verified too.
5. Apply the changed app bundle using the first pilot's Fleet-native helper,
   retaining GitRepo labels and refreshing its values Secret. Require the
   expected target mount and replica count before trusting rollout status.
6. Verify Fleet Ready, replica placement/health, config permissions/checksums,
   updater process state and FlareSolverr API/ingress. Trigger native NAS backup
   and record the three target backups. Keep original PVCs/PVs for rollback.

The DuckDNS values Secret is left unchanged; Fleet `valuesFrom` continues to
provide its credentials. ddclient's runtime cache remains outside `/config`;
FlareSolverr sessions remain process-local and a restart drops existing sessions.
No active-active DNS updater or shared browser profile is introduced.

## Rollback

Stop the affected target app and wait for its writer to exit. Restore its
original existingClaim (or original chart-created config claim settings) in
Fleet values and apply through Fleet. Verify the original claim is mounted,
then check the app before proceeding. Original files are a cutover-time recovery
point: reconcile any later configuration edits first instead of discarding them.
Do not delete either source or target data automatically. A failed post-cutover
check requires inspection; the script does not blindly overwrite live state.

`/tmp/longhorn-batch2-originals` holds runtime source definitions and original
repository files during this session. Durable claim names and rollback intent
are documented here; copy private original configuration to a secure backup
location rather than committing it to Git.
