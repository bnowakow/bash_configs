# Required maintenance mode for all PVC migrations

**Standing user instruction, 27 October 2026:** perform every PVC migration
with application workloads temporarily scaled down to **zero replicas across
the cluster**. This applies to small and large PVCs, database and file storage,
and migrations between storage classes. Stopping only the application whose
PVC is being moved does not satisfy this requirement.

## Reason

During PVC migrations with other applications running, this cluster repeatedly
showed severe I/O pressure spikes, etcd/API readiness failures and k3s restarts.
The underlying reason is **unknown**. Do not assume modest application usage,
free disk space, or a low copy bandwidth makes concurrent application workloads
safe here. Temporarily stopping applications is the required mitigation until
the user changes this instruction.

During the Mailpile migration, 45 previously active workloads were stopped and
six CronJobs suspended. Copying subsequently advanced with observed I/O PSI at
zero. This is operational evidence for the maintenance procedure, not proof
that an underlying disk, ZFS, database, or control-plane fault was repaired.
See [the Mailpile maintenance record](migrations/mailpile-2026-10-26/MAINTENANCE.md).

## Procedure

1. **Save the restoration baseline before changes.** Record workload namespaces,
   kinds, names, UIDs and replica counts; CronJob suspension states; and any
   reconciliation/autoscaling settings that will be changed. Keep full objects
   containing credentials private. Do not use failed or partial API inventories.
2. **Prevent applications from restarting automatically.** Temporarily suspend
   the relevant Fleet/GitOps reconciliation, autoscaling and scheduled
   application/maintenance jobs. Save their original states. Coordinate active
   backups; keep migration-required backup/restore jobs available.
3. **Scale applications down cluster-wide.** Include unrelated application
   workloads and their databases, not just the migration source. Stop application
   frontends/workers before their databases and allow graceful termination.
   Keep essential Kubernetes/control-plane services, DNS, networking/ingress,
   admission webhooks, Longhorn managers/engines/CSI and transfer helpers running.
   Keep an application providing essential infrastructure, such as AdGuard DNS,
   running if stopping it would break the migration; document that dependency.
4. **Verify actual shutdown.** Confirm desired and current replica counts are
   zero, source writers are gone, and no other helper/job is writing the source
   claims. A scale command succeeding is insufficient. Investigate stale Pod
   records instead of assuming they prove a process is running or stopped.
5. **Verify storage and control-plane readiness.** Check both APIs, stable k3s
   restart counts, low host I/O pressure, real physical backing-pool headroom,
   mounted filesystem capacity, and live replica/engine health. Preserve source
   PVCs and rollback data. Maintenance mode does not waive these checks.
6. **Migrate with conservative I/O limits.** Keep applications stopped during
   copying and data verification, including the backup/restore verification
   needed before cutover. Throttle bulk operations and pause under pressure.
   Record every cap change (including automatic reductions) with timestamp,
   previous/new limit, reason, I/O pressure, live-worker confirmation and observed
   outcome. Keep a cap history alongside the action log. Save and later restore
   any temporary global concurrency settings. Do not
   reduce the production replica count just to get past a capacity/health gate.
7. **Restore only the reconciliation needed for safe cutover.** Ensure Fleet
   cannot restart the old source bundle. Stage the new target claim references
   and confirm the new BundleDeployment before restoring its agent. Keep other
   applications quiesced through bulk migration work.
8. **Validate the migrated application.** Start its intended target instance
   only after copy and restore checks pass. Verify actual claim mounts, healthy
   replicas, rollout, Fleet reconciliation and service endpoints. Do not activate
   partial data or blindly restart old sources after target writes have begun.
9. **Restore applications gradually after validation.** Restore databases before
   dependent applications, using the saved replica counts. Check rollout and
   I/O pressure between workloads. Resume schedules/reconciliation carefully.
   Workloads already at zero remain zero. On failure, keep source/target ownership
   safe and explicitly document what remains stopped and how to recover it.
10. **Record the result.** Log major actions and update the migration handoff with
    shutdown scope, exceptions, before/after I/O observations, copy verification,
    remaining source PVCs, and restoration status. Do not leave temporary zero
    replicas committed as permanent application configuration.

## Reusable example

The [Mailpile maintenance script](migrations/mailpile-2026-10-26/quiesce-workloads.py),
[saved plan](migrations/mailpile-2026-10-26/maintenance-plan.json), and
[cutover/restoration watcher](migrations/mailpile-2026-10-26/maintenance-watch.py)
demonstrate saving replica counts, UID-checked changes and gradual restoration.
They are specific to that migration. **Do not execute the historical plan for a
new migration**: create a fresh inventory and restoration plan for current state.
