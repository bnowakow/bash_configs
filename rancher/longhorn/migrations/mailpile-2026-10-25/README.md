# Mailpile to Longhorn RWO — 2026-10-25

Approved scope: `mailpile-path1` data/index state -> 9Gi
`mailpile-path1-longhorn-rwo`; `mailpile-path2` GnuPG directory -> 256Mi
`mailpile-path2-longhorn-rwo`. Both use `longhorn-rwo-2replicas`, RWO,
Helm keep/Retain protection and the daily NAS backup group. Total 9.25Gi per
host / 18.5Gi aggregate replicas. One application instance, Recreate strategy.

Fresh source measurements: data 6070158848 allocated / 6921275612 apparent
bytes (43443 entries); keys 5632 allocated / 600 apparent bytes (three entries).
These are filesystem measurements, not exact future replica allocation.
The source pod was Ready on proxmox2-old; no active CloudCasa helper/kubemover
was seen. Pinned image/chart/env/mount paths are preserved. The existing image
was cached on the other node before downtime.

## Execution and evidence

`migrate.sh` protects original claims/PVs, saves source metadata under
`/tmp/longhorn-mailpile-originals`, stops the sole writer and requires its old
pod to exit before copying. Pre-cutover failure restores the source replica
count; target references are materialized only after backup/restore checks.

`manifest-check.py --copy` uses GNU `cp -a --sparse=always`, syncs each target
filesystem, then compares source/target contents and metadata. The private
manifest records SHA256/size for every regular file, UID/GID/mode, directories,
symlinks and hardlink relationships. Only aggregate counts are logged. It is
stored on the temporary local-path evidence PVC, never committed or printed.

`check-keyring.py` uses the unchanged app's Python 2/GnuPG 1.4.23 to list/parse
public and secret key metadata in a disposable CLONE of the mounted key tree.
Key identities, private contents and mail are not printed/decrypted. Original
and actual target key files are untouched. Empty valid keyrings are permitted;
all files in the mail/index tree, including app-managed encrypted state, are
independently covered by the complete manifest.

Mailpile remains stopped while a read-only holder Pod keeps both new targets
attached. A native daily NAS backup run creates quiesced backups of the same
verified state. `prepare-restore.py` selects both fresh Completed backups,
creates temporary Delete-policy Longhorn classes/claims, and runs an isolated
restore Job. The restored trees must match the entire stopped-copy manifest,
including all message/index/key bytes and permissions/link relationships; the
cloned GnuPG check is repeated. No Mailpile application process or mail/network
action is launched during isolated verification.

Only then is the holder removed and the app applied via Fleet on its new claims.
Validate desired/available replicas, both mounts, Fleet readiness, two healthy
storage replicas and both HTTPS hosts. Cleanup scratch restores/evidence/tooling
after success, preserving source rollback claims and backup/copy Job evidence.
Read RESULTS.md for actual counts, IDs and limitations.

## Rollback

Stop the new writer and wait for its pod to exit. Restore both original claim
references together using saved Fleet definitions, apply via Fleet preserving
ownership/targeting, then start one instance. Returning to older source state
requires deciding how to reconcile new mail/index/key changes since cutover.
Do not run both copies or overwrite a live mail/index directory. Source PVCs
are historical rollback copies, not additional live storage.
