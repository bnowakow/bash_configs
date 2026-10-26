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
trees, then streams a stopped-source copy at 4MiB/s. Sparse zero ranges, file
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
manifest at an 8MiB/s read limit. `check-keyring.py` uses the unchanged app image's
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
