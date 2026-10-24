# Pilot migration results — 2026-10-24

Completed live migration of Homer, Homer-without-auth and Smokeping. No other
apps were migrated. No disks were resized, no old PVCs/PVs were deleted, and
no repository changes were committed or pushed by this operation.

## Backup prerequisite

User approved downtime conditional on CloudCasa job
`6adc6cb8dc682b08a4a2f7ee` finishing. Metadata backup reached Completed at
08:31:25 UTC, but the agent continued volume transfer. Migration waited for
08:41:19 UTC (10:41:19 Europe/Warsaw), when the agent reported
`Offload completed successfully` and `Phase: Completed`, `Copy completed`.
No workloads were stopped before that final transfer completion.

## New claims and native backups

All new claims are 256Mi Filesystem/RWO on `longhorn-rwo-2replicas`: ext4,
two replicas, expandable, Retain reclaim policy. Total nominal capacity is
1Gi per storage node (2Gi aggregate replica capacity). All four volumes were
healthy with one running replica on proxmox2-old and one on proxmox3.
The original default Longhorn StorageClass remains unchanged at one replica.

| Namespace | Original retained PVC | New PVC | Native NAS backup |
| --- | --- | --- | --- |
| `apps-homer` | `homer-config` | `homer-config-longhorn-rwo` | `backup-a0db06ed866c4972` |
| `apps-homer` | `homer-without-auth-config` | `homer-without-auth-config-longhorn-rwo` | `backup-3e3d8bcacacd4392` |
| `apps-smokeping` | `smokeping-config` | `smokeping-config-longhorn` | `backup-6089d0ba33ed4246` |
| `apps-smokeping` | `smokeping-data` | `smokeping-data-longhorn` | `backup-1211e994198e4e37` |

Backup job `longhorn-system/pilot-nas-backup-20261024` completed successfully
at 09:49:23 UTC. Each production volume has the `nas-backup` group label and
is enrolled in the existing native backup schedule. Backup target remains
`nfs://nas.localdomain.bnowakowski.pl:/mnt/MargokPool/archive/Backups/rancher/longhorn`.
The job also processed the pre-existing Homer test volume under the same policy.

## Verification

- All final copy Jobs verified every source regular file by SHA256 with writers
  stopped. Both config and data containers completed successfully.
- Smokeping took longer than the first 55-second shutdown wait. A second final
  copy Job (`smokeping-longhorn-finalcopy-20261024`) ran only after confirming
  the old pod was gone, and verified config and RRD checksums before cutover.
- Both Homer Deployments and Smokeping started on proxmox2-old, whereas their
  old local-path workloads ran on proxmox3. Both Homer pods and the new config
  copy Job co-located as required for the pair of shared RWO claims.
- All five Fleet bundles Ready: `longhorn-pilot-storage`, `homer`,
  `homer-without-auth`, `homer-without-auth-config-copy`, `smokeping`.
- All ten dashboard/editor HTTPS ingress URLs returned 200 with certificate
  verification: both usual suffixes for Homer, Homer editor, without-auth,
  without-auth editor and Smokeping.
- Both editor mounts passed a real write/read-size test; the temporary test
  files were removed immediately. Existing application config was preserved.
- Smokeping probes launched; RRD files had fresh modification times. Its data
  filesystem reported about 84Mi used / 224Mi usable, 39% utilisation, with
  about 136Mi available. Config filesystem usage was 92Ki. Filesystem capacity
  is less than the nominal 256Mi block volume due to ext4 metadata/reservation.
- Native restore of Homer's new backup into a separate temporary 256Mi RWO
  volume completed. A read-only verification Job compared all regular file
  checksums against the running primary Homer claim successfully at 09:51:40
  UTC. Production files were never restored over. Temporary restore resources
  were removed after verification; production targets and backups were retained.
- The recurring Homer copy is resumed (`suspend: false`) with new claim
  references and explicit same-node pod affinity. Its renamed one-shot Job
  `homer-without-auth-config-copy-longhorn` completed successfully.
- Resuming the schedule initially hit `.spec.suspend` ownership conflict with
  the manual suspension. Aligning the live flag to false and requesting a new
  Fleet sync resolved it; Helm revision 25 reported deployed / Upgrade complete.

## Rollback and remaining follow-up

Original PVCs are still Bound; original PVs have Retain and source PVCs have
`helm.sh/resource-policy=keep`. The old without-auth source claim declaration
is intentionally retained in the copy bundle for rollback. Nothing consumes
these old claims in the current production workloads/copy schedule.
See [README.md](README.md) for coordinated claim-reference rollback. Data written
after cutover is on the new volumes: decide how to preserve it before rollback.

This proves clean rescheduling to the other host and a native backup restore;
it is not a hard node-failure/fencing drill or a storage performance benchmark.
No host was drained, powered off or force-detached. Online expansion has not
been exercised by this pilot. Keep the other migration waves gated on observing
growth, snapshot churn and replica health; do not remove rollback PVCs yet.

The pre-migration [usage inventory](../../local-pvc-usage-2026-10-24.csv) remains
historical source data, not a claim that these apps still use local-path.
