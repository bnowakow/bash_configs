# BookStack migration — 2026-10-25

Approved target: two Longhorn RWO claims, two storage replicas each:
`bookstack-config-longhorn-rwo` 256Mi and
`bookstack-mariadb-data-longhorn-rwo` 1Gi. Existing images/chart are preserved;
app and database use Recreate with one instance. No RWX shared database writers.
Use Fleet-native apply; do not install a separate Helm release.

## Locate and preserve actual state

The old `bookstack-config` local PVC was **not mounted**. Live `/config` was in
the running container layer (~5MiB), including `.env`, keys and public uploads.
`/app/www/public/uploads` links into it; other storage app/uploads paths were
empty apart from a gitignore. MariaDB 13.1.1 used ~307MiB apparent space on the
local `bookstack-mariadb-data` claim. Initial private config archive and full
logical SQL dump were saved under `/tmp/longhorn-bookstack-originals` (mode700).
These contain sensitive data and must never be committed.

`migrate-config.sh` freezes application services, archives the live config and
checks all file hashes, ownership, modes and symlinks before replacing the pod.
Shutdown needed signals as user abc for the queue/PHP workers: the root
supervisor lacks CAP_KILL across user IDs. Initial service-stop attempts aborted
and resumed the original app. Graceful pod termination also exceeded a single
55-second wait; inspect before continuing rather than rerunning a completed
stage. This directory records a one-time run, not an idempotent migration tool.

First Fleet stage mounts the new config while retaining the original DB claim.
It resolves the ephemeral-data blocker before database migration. The old config
PVC is not a backup of these live files; the verified archive and new persistent
claim are the preserved copies.

## Preserve application encryption key

The chart's secret lookup checks `bookstack-bookstack-secrets`, but renders
`bookstack-secrets`; reconciliation regenerated APP_KEY. This was caught by a
Secret comparison. The original key was copied privately to externally managed
`apps-bookstack/bookstack-preserved-app-key`, marked keep, and explicitly
referenced by the app values. No secret material is in this repository.
The runtime key is checked against the original. Back up this Secret with the
namespace and restore it **before** installing the app after disaster recovery.
The chart-generated unused key must not become the application's active key.
Database credentials are preserved. See RESULTS.md for final verification.

## Database and independent NAS restore gate

`migrate-database.sh` stops the app, captures extended checksums of every
BookStack table, then stops MariaDB and mounts its old claim read-only.
`copy-database.py` copies at 4MiB/s, preserving ownership/modes and verifying
SHA256 bytes. The original DB remains untouched. The exact MariaDB image starts
the target in isolation with only a Unix socket, no network or event scheduler;
all-database table checks and matching BookStack checksums are required.
The isolated database is stopped cleanly afterward.

`backup-and-restore.py` takes a native NAS backup of the two quiesced targets
using a temporary group, restores both to independent scratch claims, verifies
file hashes/metadata and starts/stops the restored MariaDB to repeat its checks.
Only after success and scratch/helper cleanup does it release the private marker
that permits final Fleet cutover. Production recurring NAS group stays enabled.
Temporary volumes are Delete; production claims remain keep/Retain.

The scripts retain old local claims/PVs. On pre-cutover DB failure, stop the
helper before resuming the original DB with the already-persistent config.
After cutover, any rollback must stop all writers and reconcile newer data
before using the stale original DB. Do not run two database copies as backends.
Mailpile stays last. See RESULTS.md and the current storage/priority summaries.

## Concurrent-session guard and copy retry

Another Codex session had scaled BookStack during this work. Before the final
copy both app/DB replicas were confirmed zero. A restart watcher records any
unexpected replica increase in the private `concurrent-writer-detected` marker;
backup/cutover is refused if it exists. Original source file hashes/metadata are
rechecked against the stopped-copy manifest both before backup and immediately
before cutover. The guard is released only for the intentional final rollout.
Other sessions must leave BookStack and MariaDB unchanged during migration.

The first database verification had a false positive: a broad grep matched the
valid table name `failed_jobs`. Its safety handler restored the original service;
the filter was corrected to match diagnostic words, and a fresh stopped copy
replaced the stale staging data. The final source/table/NAS checks refer to that
fresh copy, not the failed attempt. No database corruption/repair is implied.

## Major-action audit

`ACTIONS.log` records UTC timestamps for major migration steps, validation
outcomes, resource changes and failures. `action_log.py` appends entries without
logging Secret data, SQL dumps, file contents or stdin. Entries reconstructed
from earlier evidence are explicitly marked HISTORICAL; their timestamps are
when the history was recorded. Private detailed evidence stays under `/tmp`.
