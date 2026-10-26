# Docker Mailserver migration handoff — staging created

Updated 2026-10-26 13:53 CET. The user explicitly directed starting this
migration. This authorizes the Mailserver work as a task-specific exception to
the still-recorded 55Gi administrative production migration cap; it does not
change the cap for later applications. Mailpile remains last.

## Live state

- Source Deployment `apps-docker-mailserver/docker-mailserver` remains Ready
  1/1 on proxmox3, using all four original `local-path` PVCs. No source
  workload, Fleet app values or original data has been changed.
- Fleet bundle `longhorn-docker-mailserver-storage` is Ready 1/1. Its four
  target claims are Bound with the existing two-replica Longhorn StorageClass:
  config 256Mi, mail data 28Gi, logs 256Mi, state 256Mi (28.75Gi total per
  host). Each target is retained and opted into the NAS recurring backup job.
- The four target Longhorn volumes currently show `detached`, `unknown`
  robustness and zero actual data. They have not yet been mounted by a helper.
- Live measured source directory sizes (KiB from `du -sk`): config 66,
  `/var/mail` 20,416,359, `/var/log/mail` 1,794, `/var/mail-state` 20,224;
  approximately 19.5GiB total. This is a live measurement, so repeat after
  stopping the writer before final copy verification.
- Existing source PVC requests are 1Mi, 10Gi, 1Gi, 1Gi. The 10Gi data request
  is smaller than actual use; the target is 28Gi based on the previous apparent
  size measurement (~22.3Gi) plus growth buffer.
- The completed CloudCasa job `6ade68a4b2e51cc637fbc182` is not accepted as a
  Mailserver data backup: its file-copy coverage of these local-path claims was
  not verified. No source or target backup/restore has been completed for this
  migration yet.

## Capacity at 2026-10-26 13:53 CET

Both Longhorn disks are Ready/Schedulable, each with 147.09GiB maximum. After
staging, scheduled capacity is 76.03GiB on proxmox2-old and 76.04GiB on
proxmox3; peer reservation is 7.82GiB and local reservation zero. The peer
therefore has about 63.24GiB nominal room after reservation and scheduling;
local has about 71.05GiB.

The proxmox2-old `rpool` is 236GiB, allocated 146.36GiB, free 89.64GiB. After
a 20% free-space floor (47.20GiB), physical headroom is about 42.44GiB. Local
proxmox3 `rpool` is 472GiB, allocated 154.13GiB, free 317.87GiB, leaving
about 223.47GiB above its 20% floor. Recheck during copy; Longhorn capacity is
sparse and does not guarantee pool backing. The peer SSD's degraded
reliability warning persists.

At the time of staging, direct API `/readyz?verbose` passed, both etcd voters
committed health proposals (~18ms), local I/O PSI avg10/avg60/avg300 was
0/0.03/0% (some), peer 0/0/0.11% (some). Local k3s restart count was 60.
These are point-in-time checks, not a guarantee of stability under a 20GiB
copy. Stop and recheck if API readiness fails, restart counts rise, or I/O PSI
climbs materially.

## Next steps and gates

1. Prepare a source backup on NAS or verify CloudCasa file-copy inclusion and
   restore coverage for all four existing local-path claims. Do not represent
   Kubernetes object metadata backup as mail data protection.
2. Build and validate a bounded, metadata-preserving copy helper. The existing
   Mailserver image does not include `rsync`; do not improvise an unthrottled
   bulk copy. Pin any helper to proxmox3 because the source local-path PVs are
   node-local. Source mounts must be read-only during copy.
3. Take a live warm copy only if useful, then stop the Mailserver cleanly and
   take a final quiesced copy/sync of all four claims together. Verify content,
   ownership, modes, links and sizes without printing mail contents or secrets.
   Keep the original local-path claims and PVs intact.
4. Keep target claims unused by the app until the stopped-copy verification
   passes. Run fresh Longhorn NAS backups for all four target volumes, restore
   them into isolated claims, and compare against the verified copy before
   changing app values.
5. Update only the Mailserver Fleet bundle to reference the four Longhorn
   claims, preserving image, environment, Secret/Certificate, Services and
   mount paths. Apply with the Fleet-native helper and verify BundleDeployment,
   pod mounts, SMTP/IMAP health, Longhorn health and two distinct-node replicas.
6. Keep all original claims and PVs for rollback until explicit acceptance.
   Do not start another Mailpile migration during this work.

No source stop, copy, app cutover, or cleanup has occurred yet. Record
timestamped actions and final results here before declaring the migration done.

## Warm copy progress — 2026-10-26 14:56 CET

The first helper attempt at 13:52 CET stopped on a Linux `chown` permission
error after copying only disposable staging data. The source was mounted
read-only and the production Deployment remained Ready; no source files were
changed. The staging-only partial copy was cleared by the revised helper, which
now has the minimum `CHOWN`, `FOWNER` and `DAC_OVERRIDE` capabilities needed to
preserve file ownership and modes.

The retry started at 14:43:47 CET, pinned to proxmox3, with the four source
claims read-only and a 4MiB/s copy limit. At 15:00:59 CET its sanitized log
reported **4.17GB copied** from `/var/mail`. All four target Longhorn volumes
were attached and reported healthy with two replicas; the source Mailserver
remained Ready 1/1 at the latest workload check. Both API readiness checks and
etcd voter health passed; restart counts remained 60 / 0. At the latest sample
local I/O PSI avg10 was 0.23% (some) / 0.01% (full), peer was 2.61% / 1.36%.
These are point-in-time samples; continue monitoring and stop the helper if
readiness, restarts or I/O pressure deteriorate.
