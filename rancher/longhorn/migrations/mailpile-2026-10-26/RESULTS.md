# Mailpile migration completed — 2026-10-28T18:28:35+00:00

## Original host directories removed — 2026-10-28T19:18:10.322549+00:00

At the user's explicit request, removed both obsolete Mailpile local-path directories on proxmox2-old using idle I/O priority and nice19. Verified ordinary non-symlink directories and no source mounts across process mount namespaces before deletion; verified both paths absent afterward. Their last measured filesystem allocation totaled 8,991,901,184 bytes (~8.37GiB). Longhorn data was untouched. ZFS free bytes before/after were 39,343,177,728 / 38,902,493,184; concurrent storage activity and deferred frees mean no immediate physical-pool gain can be attributed from these samples. API instability prevented a complete fresh target-health audit; Mailpile Pod was Ready and data volume healthy in successful prechecks.

## Original PV object deletion — 2026-10-28

Deleted both Released original Mailpile PV objects (`pvc-efd00fa3-e42b-4129-85f9-2a2c36912dcc`, `pvc-3d4c4ac7-14b9-43fd-a5de-55afb60accc7`) at the user’s request, with UID/resourceVersion preconditions. Verified deletion. Their Retain policy preserved the original host directories; disk space has not been reclaimed. Longhorn target PVs were unchanged.

## Original PVC cleanup — 2026-10-28 19:12 UTC

Mailpile was verified Ready using only `mailpile-path1-longhorn-rwo` and `mailpile-path2-longhorn-rwo`; both Longhorn volumes were healthy. No Pod referenced either original claim. Deleted `apps-mailpile/mailpile-path1` and `mailpile-path2` with UID/resourceVersion preconditions. Both original PVs remain **Released / Retain**, preserving their host data; this operation does not reclaim disk space. No target claims or running workloads were changed. See ACTIONS.log.

**Subsequent runtime outage — 2026-10-28T18:56:07+00:00:** both Mailpile volumes are degraded again and HTTPS returns503/no available server; both APIs intermittently unready, peer full I/O PSI74.2%. Earlier verification/restoration passed, but current runtime health has regressed. See [incident](RUNTIME-OUTAGE-2026-10-28.md).


Mailpile now runs on **12Gi data + 256Mi keys**, RWO with **two healthy replicas
on distinct hosts**. One app instance, Recreate. Current chart/image/env and
Opaque Secret data were preserved. Actual pod target mounts, Fleet deployment
IDs/Ready, both HTTPS endpoints (200 after redirects) and original source
keep/Retain protection passed final checks.

Stopped-copy logical data: **10,315,431,773 bytes**; data entries:
**78,230**. Every copied regular-file chunk was read
back and source/target SHA256 compared. Full metadata, ownership, modes,
timestamps, sparse content, symlinks and hardlink relationships were preserved.
An API readiness gap blocked the initial cutover. A fresh full original-source
hash/metadata/link recheck passed before recovered cutover. Scratch restore root
timestamps were restored to the expected manifest values; strict full restore
verification and cloned keyring checks then passed.

Quiesced native NAS backups of both targets were independently restored and
verified against the complete manifest; cloned GnuPG parsing passed using the
unchanged app image. No messages were decrypted/sent in isolated checks.
The disposable restore used one strict-local replica on proxmox3 only, to avoid
extra peer-pool pressure. Production retained two replicas. Scratch restore
claims/classes/helpers and temporary backup membership were cleaned up.

File transfer started at **256KiB/s**, then resumed with verified file reuse
and live cap adjustments at user request; hashing caps were adjusted live under
both-host pressure monitoring.
Every cap change and observed outcome is recorded in **TRANSFER-CAPS.md**.
The rate monitor watches both hosts, pauses under pressure and reduces the copy
cap to256KiB/s if necessary; ACTIONS.log records actual adjustments.
high host PSI pauses work without catch-up bursts. Native backup/restore and
rebuild concurrency were temporarily limited to one. Those global limits
remain at one for now; previous values are recorded privately for an operator
to restore after stability review. Peer manager recovery, unverified staging
replacement and bounded free-block reclamation are recorded in ACTIONS.log.
No storage finalizer was forced. Stale Pod API records were cleared only after normal deletion stalled and
exact-UID host cgroup audits confirmed no live workload remained. No storage
engine process was killed by those API record deletions.

Private stopped-copy manifest SHA256: `ce30de35b64360b047e198ab0688ef770f233070d8dc9fd9a6b63bea14f98986`. Its filenames and all Secret/
mail/key contents remain outside Git under `/tmp/longhorn-mailpile-20261026`.
Original local source PVCs/PVs are retained as stale rollback copies. Do not
return to them without stopping target writers and reconciling later mail.

Login, mail reading/indexing and normal fetch behavior still require user
functional testing. The underlying peer NVMe/I/O reliability problem is not
claimed repaired by this migration. See [actions](ACTIONS.log), [handoff](HANDOFF.md)
and [procedure](README.md).

## NAS backup records

- data: `backup-8aa200a6b8d94045`, created `2026-10-28T08:11:22Z`, source volume `pvc-775212e9-ac49-4664-9dd0-a239dc72bf1c`.
- keys: `backup-5a7db56e56314650`, created `2026-10-28T07:59:46Z`, source volume `pvc-dbe22a3b-837b-48c9-a83d-4b710065bc12`.

## Application restoration completed — 2026-10-28T18:41:14+00:00

All52 maintenance targets match their Fleet desired replica/suspend states and are Ready where applicable. Filebot remains0 and Homer-test2. See [RESTORATION.json](RESTORATION.json). One unchanged pre-existing Fleet exception remains: CloudCasa manager container-template drift; its live template matches the pre-maintenance snapshot exactly, its desired deployment ID is applied and its one replica is Ready. The working agent image was not reverted.

Post-restoration I/O/API instability caused stale peer Longhorn/CSI/instance-manager records and temporary degraded volumes. Exact-UID pause-only cgroup audits preceded stale-record cleanup; peer components recovered and both Mailpile volumes returned healthy with two replicas. Five stale deleting application records were similarly cleared after proving no app process remained. Cleanuparr required normal cleanup of its obsolete CSI attachment; no force detach/finalizer change. BookStack config was100% full and expanded256→512Mi through Fleet; its filesystem now464Mi total,219Mi used,240Mi free, and BookStack is Ready. Homer config-copy no longer declares its unused local-path claim; its Fleet bundle is Ready.

Final live inventory:46 Bound Longhorn claims,79.259765625Gi requested, including idle retained/test claims. Historical CSV suggested sizes are not live allocation totals. No original Mailpile PVC was deleted; no commit/push performed.
