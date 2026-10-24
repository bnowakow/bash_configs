# Bindery, Bazarr and Authelia — singleton Longhorn RWO

Approved next batch: three 256Mi claims, two replicas each, one application
writer and Recreate strategy. Order: Bindery, Bazarr, Authelia (authentication
is interrupted while Authelia is stopped). NAS media mounts are preserved.

Fresh source apparent sizes: Bindery 25.16MiB, Bazarr 69.24MiB, Authelia 0.36MiB.
Read-only helper Jobs measured the source mounts; no active CloudCasa helper or
kubemover was present at preflight. Original claims/PVs are kept for rollback.

Apply `longhorn-sqlite-next-storage` using the existing Fleet-native
`../pilot-2026-10-24/apply-bundle.sh` helper, then run `migrate-one.sh APP` one at
a time. The helper preserves source PVCs with Helm keep/PV Retain, requires the
old pod to stop, copies the entire tree including WAL/SHM files, verifies SHA256
for every regular file and checks SQLite on the target before applying the app
bundle. Copy/check failure restores the original replica count before cutover.
After cutover, inspect failures before changing either data copy.

Bindery's vendored chart now accepts `persistence.config.existingClaim`; when
set, its Deployment uses that claim and its chart-owned PVC is not rendered.
Without the setting its original claim rendering remains available. TrueCharts
Bazarr/Authelia use their existingClaim setting. Pinned images/charts, credentials
and Authelia encryption/session secret references are preserved.

Original repository files and live workload/PVC metadata are saved under
`/tmp/longhorn-sqlite-next-originals` for this session. To roll back: stop the
new writer, restore original Fleet claim definitions (including Bindery's chart
PVC settings), apply via Fleet, and start exactly one instance. Returning to an
older source loses subsequent changes unless explicitly reconciled; never run
both copies or overwrite a running SQLite database.

See RESULTS.md for live validation, backups and any limitations.
