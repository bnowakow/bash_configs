# Docker Mailserver migration handoff — cutover complete

Updated 2026-10-26 17:34 CET. The user explicitly directed starting this
migration. This authorizes the Mailserver work as a task-specific exception to
the still-recorded 55Gi administrative production migration cap; it does not
change the cap for later applications. Mailpile remains last.

## Live state

- Deployment `apps-docker-mailserver/docker-mailserver` is Ready 1/1 on
  proxmox3, now using all four Longhorn PVCs. Fleet values were switched and
  Fleet reports Ready 1/1. The original `local-path` PVCs were deleted at
  17:30 CET on user instruction. At 17:34 CET the old local data directories
  and four retained PV objects were removed to reclaim the storage. See cleanup
  record below.
- Fleet bundle `longhorn-docker-mailserver-storage` is Ready 1/1. Its four
  target claims are Bound with the existing two-replica Longhorn StorageClass:
  config 256Mi, mail data 28Gi, logs 256Mi, state 256Mi (28.75Gi total per
  host). Each target is retained and opted into the NAS recurring backup job.
- All four target volumes contain the completed warm copy and final
  stopped-writer sync. They are attached to the Mailserver pod and report
  `healthy` with two replicas each. Their measured actual sizes total about
  23.45GiB: config 33,849,344 B, data 24,951,394,304 B, logs 38,752,256 B,
  state 133,902,336 B. These were the target sizes at cutover; post-cutover
  writes now go to the Longhorn volumes.
- Live measured source directory sizes (KiB from `du -sk`): config 66,
  `/var/mail` 20,416,359, `/var/log/mail` 1,794, `/var/mail-state` 20,224;
  approximately 19.5GiB total. This is a live measurement, so repeat after
  stopping the writer before final copy verification.
- Existing source PVC requests are 1Mi, 10Gi, 1Gi, 1Gi. The 10Gi data request
  is smaller than actual use; the target is 28Gi based on the previous apparent
  size measurement (~22.3Gi) plus growth buffer.
- The pre-cutover final manifest is saved privately at
  `/tmp/mailserver-cutover-final-manifest-20261026.json` (mode 0600); it includes
  paths and should not be printed. The user confirmed a CloudCasa backup exists
  for the source local-path PVCs; its job and restore contents were not
  independently inspected here.

## Capacity at 2026-10-26 16:52 CET

Both Longhorn disks are Ready/Schedulable, each with 147.09GiB maximum. After
staging, scheduled capacity is 76.03GiB on proxmox2-old and 76.04GiB on
proxmox3; peer reservation is 7.82GiB and local reservation zero. The peer
therefore has about 63.24GiB nominal room after reservation and scheduling;
local has about 71.05GiB.

The proxmox2-old `rpool` is 236GiB, allocated 167.51GiB, free 68.49GiB.
After a 20% free-space floor (47.20GiB), physical headroom is about 21.29GiB.
Local proxmox3 `rpool` is 472GiB, allocated 174.32GiB, free 297.68GiB,
leaving about 203.28GiB above its 20% floor. The peer SSD's degraded
reliability warning persists. A second full two-replica restore copy of the
23.45GiB target would exceed the peer's remaining physical margin; do not
attempt it unless backing capacity or the restore plan changes.

Longhorn Node accounting: proxmox2-old maximum 147.09GiB, available 99.45GiB,
scheduled 76.03GiB, reserved 7.82GiB; proxmox3 maximum 147.09GiB, available
97.15GiB, scheduled 76.04GiB, reserved zero. Nominal room after scheduling
and reservation is 63.24GiB / 71.05GiB respectively. Keep nominal Longhorn
capacity distinct from physical pool headroom.

At staging, direct API `/readyz?verbose` passed and both etcd voters committed
health proposals (~18ms); local k3s restart count was 60. During the warm copy,
both APIs remained ready and restart counts stayed 60 / 0. PSI had brief peaks
around 16% `some` / 12% `full` on proxmox2-old and 13% / 9% on proxmox3; prompt
rechecks subsided. No API failure or restart occurred. Continue monitoring and
pause the copy if readiness fails, restart counts rise, or pressure becomes
sustained and materially higher.

## Copy and source restoration — 2026-10-26 16:52 CET

The stopped-writer sync copied 159,604,646 bytes across 188,698 entries. The
helper compared file content and metadata while source claims were read-only.
After the sync completed, the Deployment was briefly restored to 1/1 on the
original claims; the source pod was `docker-mailserver-7588cf5b54-sdsqf`. Its
queue count was one shortly after restart (pre-stop count was zero). The
original claims remain intact.

## Cutover — 2026-10-26 17:16–17:20 CET

The user confirmed a CloudCasa backup exists for the source local-path PVCs.
Mailserver was stopped and a final sync recopied 57,887,071 bytes across
188,699 entries. The final manifest was exported to the private path above.
Fleet values were changed to the four `*-longhorn-rwo` claims and the
Fleet-native helper applied bundle `docker-mailserver` at 17:16:35 CET. Pod
`docker-mailserver-54bfbbfb58-xx2gb` became Ready 1/1 on proxmox3, mounting all
four target claims. Fleet reports Ready 1/1; the Service has external IP
10.0.0.50 and an EndpointSlice targets the new pod. Postfix and Dovecot report
RUNNING. SMTP 25, IMAP 143 and IMAPS 993 accepted TCP connections through the
Service IP. All four Longhorn volumes are attached, `healthy`, and have two
running replicas on distinct nodes (`proxmox2-old` and `proxmox3`). The
temporary copy helper was deleted. The original source PVCs were later deleted
on user instruction; their retained PVs and local data remain, but rollback
would require deliberate PV/PVC recovery.

The production request cap remains 55GiB generally; this task-specific
authorization does not raise it for other apps. Mailpile remains last.

## Original local-path storage reclamation — 2026-10-26 17:30–17:34 CET

After confirming the live Deployment used only Longhorn claims and no pod
mounted the originals, the user instructed deletion of the four source PVCs:
`docker-mailserver-mail-config`, `-mail-data`, `-mail-log`, and `-mail-state`.
All four PVCs were gone; the retained PV specs identified these exact local
paths under `/var/lib/rancher/k3s/storage/migrated-from-nas/` on proxmox3:
`docker-mailserver-mail-config`, `-mail-data`, `-mail-log`, and `-mail-state`.
They were confirmed to be ordinary directories on the root ZFS filesystem, not
mount points. Their apparent usage was about 20GiB total, mostly the 20GiB mail
data directory. Only those four directories were removed, then only their four
released PV objects were deleted. A final check found no matching directories
or PV objects. Current `rpool` reports 155GiB allocated / 317GiB free; this is
a post-cleanup reading, not a precise before/after allocation delta. Mailserver
remained Ready 1/1 on Longhorn and all four Longhorn volumes remain healthy
with two replicas. The old local-path data has been permanently removed.

## Warm copy progress — 2026-10-26 16:25 CET

The first helper attempt at 13:52 CET stopped on a Linux `chown` permission
error after copying only disposable staging data. The source was mounted
read-only and the production Deployment remained Ready; no source files were
changed. The staging-only partial copy was cleared by the revised helper, which
now has the minimum `CHOWN`, `FOWNER` and `DAC_OVERRIDE` capabilities needed to
preserve file ownership and modes.

The retry started at 14:43:47 CET, pinned to proxmox3, with source claims
read-only and a 4MiB/s limit. It reached about 23.5GB before stopping at a
runtime special file in `/var/mail-state`; no source or app data was altered.
The resume pass skipped unchanged files by metadata, recopied **166,547,445
bytes**, skipped runtime-only sockets/FIFOs, and completed all four volumes
with **188,697 entries** at 16:25:21 CET. Newly copied files were SHA256 checked
against readback; unchanged files were previously readback-checked and matched
source size/mtime/mode/ownership. The source Mailserver remained Ready 1/1.
Target replica pairs were healthy while attached. The helper later exited, so
it was recreated for final sync; the resulting manifest was exported to private
`/tmp/mailserver-final-copy-manifest-20261026.json`.

At completion, both APIs were ready, k3s restart counts remained 60 / 0, local
and peer I/O PSI were below 1.4% `some` / 0.2% `full` over 10 seconds. These are
point-in-time readings, not a guarantee under the final sync.
