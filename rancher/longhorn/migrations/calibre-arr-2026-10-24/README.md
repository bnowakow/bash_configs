# Calibre group, Profilarr and Radarr — 2026-10-24

Approved next batch: Calibre, Calibre Web, Kavita, Profilarr and Radarr.
Six target claims use `longhorn-rwo-2replicas` with two storage replicas:
three Calibre private configs 256Mi each, shared library 1Gi, Profilarr config
1Gi and Radarr config 1Gi. Total 3.75Gi per node / 7.5Gi aggregate replicas.

## Shared-library procedure

All Calibre state and its maintenance consumer move as a single unit.
`migrate-calibre-group.sh` saves original workloads/PVCs/CronJob under
`/tmp/longhorn-calibre-arr-originals`, rejects unknown/active maintenance
consumers, protects original claims with Helm keep/PV Retain, and suspends the
cover-maintenance CronJob. It scales Calibre, Calibre Web and Kavita to zero,
waits for every old pod to exit, then checks again that no source consumer is
alive before copying the four complete trees.

The Python copy/check Job preserves metadata and WAL/SHM files, checks SHA256
of every regular file and runs SQLite quick_check on target database files.
Copy/check failure restores original app replicas and CronJob suspension before
cutover. After successful checks, the helper applies all three app bundles via
Fleet, waits for both new config/library references and singleton readiness,
and applies the updated maintenance bundle. During this execution the manifest
was staged with suspend=true until target references had been verified; its
final committed-to-disk setting is suspend=false after validation.

Verify all apps and maintenance reference the new library/web-config claims and
share explicit `kubernetes.io/hostname: proxmox2-old` placement. Calibre owns
the writable library mount; Calibre Web and Kavita retain read-only mounts.
The maintenance extraction init container can write the library, and its final
thumbnail step writes only web-config. The original NAS books/import mounts
remain unchanged. Resume maintenance with `spec.suspend: false` in its Fleet
manifest, then apply the maintenance bundle again after validation.

A hard node selector preserves existing placement and enforces shared RWO even
for read-only consumers. Longhorn replication does not provide application HA.
A future grouped node move must update every app and maintenance selector
consistently after stopping/detaching the shared writer.

## Profilarr and Radarr

Run `migrate-one.sh profilarr` then `migrate-one.sh radarr`. Each stops its sole
writer, copies/verifies the whole config claim, applies through Fleet and checks
the new mount and rollout. Profilarr's custom chart requires
`persistentVolumeClaims: null`; it omits Deployment replicas, so the helper
restores one replica only after the new target claim is installed. Radarr uses
TrueCharts existingClaim. Recreate and one replica remain required.

No source databases are repaired/checkpointed during copy; original mounts are
read-only. Stop before copying and preserve all sidecars. All pinned images,
chart versions, credentials and unrelated settings remain unchanged.

## Rollback

Stop new writers and suspend maintenance before changing either data copy.
Restore original Fleet definitions/claim references from the saved repository
files and apply preserving GitRepo ownership. For Calibre, restore all three
private configs, the shared library and maintenance claims together. Check
original mounts and ensure at most one owner before restarting. Resume the
original maintenance state only after all apps are ready. New writes since
cutover need an explicit reconciliation decision before using older sources.
Never start both copies or overwrite a running SQLite database.

`calibre-storage` continues to own the retained original library/web-config;
new claims belong to `longhorn-calibre-arr-storage`. Other original chart claims
also remain rollback copies. See RESULTS.md for verification and backup evidence.
