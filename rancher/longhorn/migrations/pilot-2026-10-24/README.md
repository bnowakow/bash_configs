# First Longhorn pilot — 2026-10-24

Scope: Homer, Homer-without-auth and Smokeping, four 256Mi RWO claims,
two Longhorn replicas each. No disk resizing, no database app migrations.
User approved downtime, conditional on successful completion of CloudCasa job
`6adc6cb8dc682b08a4a2f7ee`. Kubernetes metadata backup completion alone is not
sufficient: wait for CloudCasa's subsequent volume-data transfer to finish.

Durable target StorageClass/PVCs are managed by the Fleet bundle
`fleet/infrastructure/longhorn-pilot-storage`; the ordinary Longhorn class and
existing test RWX volumes remain unchanged. Each target has Retain/keep
protection and joins the existing `nas-backup` recurring job group.

## Cutover sequence

1. Record backup completion, source claims/PVs, replica counts, active Jobs and
   pre-migration ingress responses. Save live Bundle specs outside Git.
2. After the backup gate, protect source PVs with Retain and source PVCs with
   `helm.sh/resource-policy=keep`. Apply the new storage bundle through Fleet;
   wait for Bound and verify two replicas across the two hosts.
3. Suspend the hourly Homer config-copy CronJob, check no running copy Job,
   then stop the two Homer Deployments. Stop Smokeping only for its own copy.
4. Apply the appropriate copy Job JSON in this directory, wait for completion
   and inspect both container logs. Source mounts are read-only; each file's
   SHA256 must verify against the stopped source. Original data is retained.
5. Apply the updated Homer Fleet values/claim references, start primary Homer,
   then update the copy bundle and Homer-without-auth. Co-locate both Homer
   pods and all copy Jobs because the RWO targets are shared on one node.
   Apply Smokeping with both new claims. Preserve existing GitRepo labels.
6. Verify Fleet readiness, app mounts, both HTTPS domains per app, editor
   endpoints, Smokeping RRD writes, Longhorn health/replica placement and backup
   enrollment. Resume the hourly copy only after checking its new claim mounts.
7. Trigger and verify a native Longhorn backup of the pilot volumes and record
   backup IDs. Do not remove old PVCs/PVs or data directories during this pilot.

## Rollback

Suspend the Homer copy CronJob before rollback. Stop the migrated workload(s),
wait for writers to exit, and restore each original claim reference from the
pre-cutover files. Homer: `homer-config`; without-auth: `homer-without-auth-config`;
Smokeping: `smokeping-config`, `smokeping-data`. Restore the copy Job/CronJob
references together. Apply through Fleet preserving GitRepo labels and start
the apps. Resume the copy CronJob only after verifying original mounts.

Old data is a cutover-time rollback point. If users have written new data to
Longhorn since cutover, decide whether to copy it back consistently before
rollback; do not run two independent writers or overwrite old data blindly.
Do not delete target volumes as an automatic failure handler.
