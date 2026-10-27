# Mailpile final migration — 2026-10-26

Authorized scope: existing local-path mail/index data and GnuPG directory to
Longhorn RWO with two production replicas. Current chart 10.0.4 and exact app
image remain unchanged. Original source PVCs/PVs stay keep/Retain until a later
explicit reclamation decision. This run supersedes the failed 2026-10-25 attempt;
old staging data is unverified and will be replaced, never merged into live state.

Fresh live measurement: data 10,102,524,988 logical bytes (~9.41GiB),
8,794,885,632 allocated bytes and 75,526 entries; key tree 600 bytes/three entries.
The old 9Gi data target is too small. Storage bundle now requests **12Gi data +
256Mi keys**, total 12.25Gi per host (two production replicas). This migration is
a task-specific authorization beyond the old 55Gi administrative cap, not a
change to that general cap. No new production replica-count policy is introduced.

## Controlled preservation

The transfer helper mounts both originals read-only and both staging targets
read-write on proxmox2-old. It runs only inspection/copy commands, not Mailpile.
Require both APIs stable, both targets attached/healthy with two replicas and
the filesystem expansion complete before stopping the sole Mailpile writer.
Protect source claims/PVs, snapshot original deployment, repo config and Secret
data privately under `/tmp/longhorn-mailpile-20261026` (mode 700).

`copy-and-verify.py copy` clears only the explicitly mounted unverified staging
trees, then streams a stopped-source copy at 256KiB/s. Sparse zero ranges, file
ownership/modes/timestamps, directories, symlinks, FIFOs and hardlinks are
preserved. Every copied chunk is read back; source/target SHA256 is accumulated
for each regular file. Complete metadata/link inventories are compared after
filesystem sync. Sockets/unsupported special files fail closed rather than
silently omitting data. Private manifests/diagnostics remain private; logs print
only aggregate progress/counts. Source files are checked for concurrent change.

During copying/backup, unexpected writer restart or loss of API health blocks
cutover. Before cutover, compare original source metadata/tree inventory again
and require the source writer still stopped. Do not activate partial staging.
Failure handling must stop the transfer helper before restoring the original
Mailpile replica, and must never blindly switch to stale originals after target
writers have resumed.

## NAS backup and independent restore

While Mailpile stays stopped and the helper holds the targets attached, label
both PVCs for a temporary Mailpile-only native NAS backup group. Wait for label
synchronization, require fresh Completed backups of both volumes, and retain
normal daily NAS membership. Do not use a whole-group backup or count a zero-
volume Job as backup evidence.

Restore both backups into temporary Delete-policy claims on **proxmox3 only**:
a separate StorageClass with `numberOfReplicas: "1"` and
`dataLocality: strict-local`, plus restore pod nodeSelector proxmox3. This is an
isolated disposable test, not a production-policy change. It avoids writing a
second ~9.4GiB replica on proxmox2-old while the production target is present.
Confirm the scratch replica placements actually match this plan before testing.
See [Longhorn storage-class parameters](https://longhorn.io/docs/1.13.0/references/storage-class-parameters/).

`copy-and-verify.py verify` compares the complete restored SHA256/metadata/link
manifest at a 512KiB/s read limit. `check-keyring.py` uses the unchanged app image's
Python 2/GnuPG 1.4 in a disposable clone, printing only public/secret key counts.
No messages are read through the application, decrypted, sent or fetched during
isolated verification. Root manifests contain filenames; never commit them.

Only after complete restore/keyring checks and scratch cleanup should Fleet
switch both claim references together, with one instance and Recreate. Verify
actual pod mounts, unchanged image/env/Secrets, both HTTPS hosts, Fleet readiness,
two healthy production replicas on distinct hosts, and backing-pool headroom.
Retain original local claims after success. Update current inventory/priority
and results; record every major action in `ACTIONS.log`.

## Current preparation health hold

The first preparation applied the 12Gi storage request and created the transfer
helper without scaling Mailpile down. Both APIs then returned 503, local k3s
restarts increased 60→62, peer service was activating with high I/O PSI. No data
copy or source mutation occurred. Require current health revalidation; do not
interpret desired 12Gi or a created helper as a finished expansion/migration.

## User-requested lower throttle

The next file copy is limited to **1MiB/s**, with metadata processing limited
to 20 entries/s on average. Independent restore verification reads at **2MiB/s**.
At the last measured 9.41GiB this means roughly 2h40m minimum for copying, plus
verification and backup/restore time; helper lifetimes are 24h. This limits the
file-transfer workload; it does not itself throttle Longhorn replica rebuilds.

The copy/verification process also pauses while host `/proc/pressure/io` reports
`some avg10 > 30%` or `full avg10 > 10%`. It resumes at the configured low rate
without a catch-up burst; metadata description is capped at 100 entries/s.
API health and a stopped source writer are separate cutover requirements.

Longhorn's documented rebuild bandwidth QoS applies to the **V2 engine only**;
these production volumes use V1. Do not set a V2 bandwidth option and assume
V1 repairs are throttled. See [rebuild QoS](https://longhorn.io/docs/1.13.0/advanced-resources/rebuilding/replica-rebuild-qos/).
An attempted temporary concurrency reduction 5→1 timed out; last reported value
remained 5. Confirm the actual setting after API recovery before changing or
restoring it. No production replica count was reduced.

## Maximum-throttle restart (26 October evening)

`start-when-ready.py` is the guarded start controller. It keeps the original app
running while waiting for both APIs, healthy two-replica targets, three minutes
of stability, low peer I/O pressure, and physical ZFS free space sufficient for
the target plus a 20% pool reserve and 2GiB buffer. Its current state is in
`STATE.json` (ignored by Git); all major actions append to `ACTIONS.log`.
Copy bandwidth is capped at 256KiB/s, restored hashing at 512KiB/s, and metadata
operations are paced. Copying pauses when host I/O PSI avg10 exceeds 10% some
or 2% full. This is deliberately slow: roughly 11 hours of data transfer alone,
plus metadata checks, backup and restore verification. Longhorn rebuild, backup
and restore concurrency are temporarily limited to one; production replicas
remain two. Longhorn internal backup/restore traffic has concurrency limits,
not the Python copier's byte-rate cap.

Preparation replaced the failed, unverified staging data PVC with clean 12Gi
`pvc-775212e9-ac49-4664-9dd0-a239dc72bf1c`. Original local-path claims are
untouched. Peer manager and instance-manager stale Pod records required recovery
after their processes had already disappeared. Bounded idle-priority FITRIM
reclaims only filesystem-free Longhorn blocks in 256MiB ranges, with pressure
pauses; it never removes files or discards allocated app blocks.

## Resume with Mailpile already stopped — 27 October

Run `start-when-ready.py --source-stopped` to resume the authorized migration
without bringing the source app back up. The controller verifies zero source
replicas and passes this mode to the coordinator. On pre-cutover failure the
coordinator stops the helper and leaves the original app at zero replicas.
Success still starts one instance on Longhorn after backup/restore validation.

The controller automatically launches/retries bounded reclamation while the
physical-headroom gate is unmet; the reclamation worker holds an exclusive
lock to prevent simultaneous discard jobs. It stops on API failure, pauses on
pressure, and resumes only at its saved offset on the next safe attempt.

The 27-Oct retry repaired missing peer manager/CSI/instance-manager processes
by replacing confirmed failed Pods. Old Pod records were removed only after
normal deletion and host cgroup verification that only inert pause sandboxes
remained. Fresh helper is Ready2/2. Verified mounted data filesystem has
11.71GiB total /11.69GiB free; keys0.218GiB total. Source mounts remain RO;
app chart/value files match the privately saved baseline. Source data untouched.

## Live rate adjustment — 27 October

User requested a modest increase from256 to512KiB/s with I/O monitoring. The
original worker had a fixed cap, so its supervisor/coordinator and remote copy
were stopped without deleting the helper or staging, and the start marker was
archived privately. `--source-stopped --resume-copy` starts the verified resume
path. Every existing regular file is compared byte-for-byte against the stopped
source before reuse; partial/corrupt files are rewritten, stale target entries
removed, and the complete manifest/metadata/hardlink checks still apply. No
manifest or copied file is trusted merely because it exists. Source remains0.

`/tmp/mailpile-rate.json` in the transfer container controls `copyKiBps` and
`verifyKiBps` (valid64–1024), plus `pause`. Updates are atomic and apply on the
next block/metadata guard. Copy defaults512KiB/s; restore hashing stays512KiB/s.
`rate-watch.py` monitors both hosts every15s, records aggregate samples in
ACTIONS.log/RATE.json, pauses at some>10% or full>2% on either host, and lowers
the copy cap to256KiB/s. Recovery requires three low samples and retains the
reduced cap. It also pauses below the peer's20% pool-free floor plus2GiB.
The monitor stops when copying finishes or migration needs review; native NAS
backup/restore have separate concurrency controls and are not byte-rate capped
by this copier. Resume-start capacity forecasts subtract target bytes already
allocated, avoiding counting the preserved staging copy twice.

Fixture verification passed: valid-file reuse without rewriting, corrupted-file
repair, sparse files, hardlinks, symlinks, FIFO, metadata/full-manifest restore
validation, stale-entry cleanup, and live256→512 cap updates/invalid-zero rejection.

Every transfer-cap change and observed result is recorded in [TRANSFER-CAPS.md](TRANSFER-CAPS.md). The27-Oct13:05 trial raised the live copy cap to768KiB/s after an earlier automatic fallback to256. At13:07, worker output confirmed768 and progress; local PSI0/0, peer0.08%some/0.02%full, no guard alert. Continuous monitoring and automatic pause/fallback remain active.

## Conditional restoration to Fleet desired state

Latest user instruction: verify migration success, then scale applications back
to Fleet desired state. See RESULTS.md for current pending status. The maintenance
watcher invokes `quiesce-workloads.py restore`, now delegated to `restore-fleet.py`
using systemPython/PyYAML. Read-only `restore-fleet.py --plan` validates ownership,
applied deployment IDs and rendered manifests before recording desired counts.
The execute path requires STATE complete and repeats final migration checks,
then restores gradually and verifies Fleet readiness. Do not restore applications
while final metadata/backup/restore/cutover validation is incomplete.

## Faster verification with live controls —27October

User requested increasing verification limits while monitoring I/O and reporting
progress. Fixed20entries/s metadata worker was checkpointed (only supervisor,
coordinator and worker stopped; helper and all staged files retained). A fresh
verified resume rechecks existing bytes before reuse; prior in-memory inventory
progress is not treated as a completed result. No data is trusted or activated
without the full checks. The old inventory estimate was~28%, not an exact count.

New requested limits: copy1024KiB/s unchanged, staged-file revalidation8192KiB/s,
restored-data hashing2048KiB/s, metadata100entries/s. All four limits now update
live from /tmp/mailpile-rate.json. Metadata valid range5–500entries/s; byte
limits64–16384KiB/s. INVENTORY_START/PROGRESS/COMPLETE print exact entry counts
and per-pass percentages; HASH_PROGRESS prints checked bytes and expected total
for restored-data verification. No message contents or filenames are printed.

The rate watcher now continues through backup/restore verification and applies
limits to both transfer and restore helpers as they become Ready. Either host
PSI some>10% or full>2%, low peer physical headroom, or missing telemetry pauses
work and reduces copy256KiB/s, revalidation1024KiB/s, restore hash512KiB/s and
metadata20entries/s. Three low samples are required before resume; reduced limits
are retained. Every accepted cap/metadata change is appended to TRANSFER-CAPS.md.
Native Longhorn backup/restore traffic has separate concurrency controls; these
Python byte limits govern the copier/hash verifier, not native engine traffic.

Fixture checks passed full copy/resume/restore with hardlinks, symlinks, sparse
files, FIFO, corruption repair, stale-entry cleanup and metadata equality; live
metadata20→100/s and independent8MiB/s revalidation limiter were also verified.

See [VERIFICATION.md](VERIFICATION.md) for the measured source totals, per-stage percentage reporting every minute, current live verification controls, the aggressive-trial fallback and the moderate4MiB/s+40entries/s trial. Every accepted adjustment remains in TRANSFER-CAPS.md.
