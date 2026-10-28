# BookStack migration results — 2026-10-25

BookStack and MariaDB now use **Longhorn RWO with two replicas**:

| Claim | Request | State |
| --- | ---: | --- |
| `bookstack-config-longhorn-rwo` | 512Mi (expanded28Oct; initial256Mi) | Live config, keys and uploads preserved from container layer |
| `bookstack-mariadb-data-longhorn-rwo` | 1Gi | MariaDB 13.1.1, one database owner |

Both Deployments use Recreate and one replica. Chart 23.0.6 and exact app/DB image
digests were preserved. No RWX database sharing or disk enlargement was enabled.

## Preservation and validation

The old config PVC was not mounted. The live `/config` (~5MiB) was archived
privately and all 1,169 entries checked by SHA256, modes, ownership and symlinks
before replacing the old pod. Public uploads resolve into `/config`; other app
storage/uploads paths contained no user uploads. Config was mounted persistently
and the app validated against the original database before the DB copy phase.
The old unused config PVC is not a backup of those formerly ephemeral files.

MariaDB used ~307MiB apparent space. A stopped copy transferred 309,476,550 bytes
across 592 entries at 4MiB/s, with source/target file hashes verified. The copied
DB started/stopped cleanly in isolation with Unix socket only, no TCP or event
scheduler. All-database table checks passed; all 41 BookStack table checksums
matched the stopped source. Full original source hashes/metadata were rechecked
before backup and again before cutover, with both source writers still stopped.

Both targets received fresh native NAS backups, restored to independent scratch
claims. Config and DB restore hashes/metadata matched the stopped targets; the
restored MariaDB started/stopped cleanly, passed all-database checks and matched
all 41 source table checksums. Scratch pods, PVCs, StorageClasses and temporary
backup-group labels/RecurringJob were cleaned up before cutover. Production
claims retain daily `nas-backup` membership. Final Fleet apply installed both
target mounts and both workloads became available.

## Encryption key and credentials

The chart looked up `bookstack-bookstack-secrets` but rendered
`bookstack-secrets`, regenerating APP_KEY during reconciliation. Secret comparison
caught this. The **original key** was retained in externally managed
`apps-bookstack/bookstack-preserved-app-key`, marked keep, and explicitly
referenced in app values. The final runtime hash matches the original; other
original Opaque Secret data remained unchanged. The chart's unused generated
Secret may still rotate; it is not the active app key. Back up/restore the
preserved-key Secret before recreating the app. No secret material is in Git.

## Runtime and rollback

Final checks confirmed actual app and DB pod target mounts, Fleet
BundleDeployment Ready with matching desired/applied IDs, both Deployments
available with Recreate, and two healthy Longhorn replicas per volume on distinct
hosts. Certificate-verified HTTPS redirects to login and the final page responds
200. Database SQL works. Interactive login, page content, uploads and attachment
workflows still require user testing; no content edits or test email were sent.

Both original local PVCs remain Bound/keep and PVs Retain. The original DB is a
stale rollback copy after writers resume; intentional rollback requires stopping
target writers and reconciling subsequent writes. The verified private live
config archive and initial full SQL dump remain in
`/tmp/longhorn-bookstack-originals` (sensitive; never commit). Do not activate two
database copies as backends.

## Retries, outage and concurrency limits

Initial service shutdown attempts aborted and resumed source services; signaling
workers as their own user resolved the missing cross-user signal capability.
One DB check falsely matched the legitimate `failed_jobs` table name; it aborted
safely, and the corrected check used a fresh stopped copy. The first NAS job
selected zero volumes and is **not** backup evidence. The successful retry
labels PVCs and waits for Longhorn's label synchronization.

Another Codex session scaled BookStack during this work. Final copy and backup
used confirmed stopped writers, a concurrent-writer guard, and repeated source
hash revalidation. Repeated etcd/API failures held migration for root-level
investigation. See [handoff](HANDOFF.md) for confirmed storage stalls and observed
restarts. The successful resumed validation/cutover ran with local k3s restart
count 27 unchanged; this does not establish repair of the underlying I/O fault.

[Major-action log](ACTIONS.log) records UTC milestones, checks, resource actions
and failures. Reconstructed historical entries are explicitly marked. Completed
production migration totals are 28 apps / 39 RWO claims / 38Gi requested
(76Gi nominal aggregate replicas). Mailpile stays local and last; its 9.25Gi
unverified staging is separate from production. See the
[current inventory](../../current-app-storage-summary-2026-10-24.md) and
[remaining plan](../../remaining-migration-priority-2026-10-24.md).

## Native NAS backup records

- config: `backup-ad93d906c6bc4b8a`, created `2026-10-25T13:30:53Z`, volume `pvc-d8b86475-1eac-413d-90ab-5534112aba20`.
- db: `backup-e70bfb5c277c4e67`, created `2026-10-25T13:30:40Z`, volume `pvc-ad162742-8668-4b9f-8c32-88f80cb56801`.

Final validation completed 2026-10-25T13:40:27+00:00. Laravel effective key also matched the original; inspected app/DB logs had no matching storage/auth/SQL errors.

## Config capacity increase — 28 October 2026

During restoration after the Mailpile maintenance window, `/config` was 100% full (219MiB used on the 256Mi claim; filesystem capacity224MiB). The same RWO/two-replica claim was increased to512Mi through its Fleet storage bundle. No source data or log files were deleted. The additional request is256Mi per replica. Final filesystem expansion/readiness is verified in the Mailpile action log.

Expansion verified28October: Fleet storage bundle Ready/applied; mounted filesystem464Mi total,219Mi used,240Mi free; BookStack Ready.
