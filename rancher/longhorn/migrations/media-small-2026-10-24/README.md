# Audiobookshelf, Scrutiny, Prowlarr — 2026-10-24

Approved size-ranked batch: Audiobookshelf config 256Mi + metadata 1Gi;
Scrutiny config 256Mi + InfluxDB 1Gi; Prowlarr config 256Mi. Five claims total
2.75Gi, nominally 2.75Gi per host / 5.5Gi aggregate with two replicas. All are
RWO on `longhorn-rwo-2replicas`; workloads remain singleton with Recreate.

Fresh sources were measured with read-only helper Jobs. Originals, including
repository settings, are recorded under `/tmp/longhorn-media-small-originals`.
No active CloudCasa helper/kubemover was present at preflight.

1. Render pinned charts and verify all external claims, unchanged images/NFS,
   singleton/Recreate and no chart-owned PVCs. Apply the new storage bundle
   through Fleet and wait for its five claims to bind.
2. Run `migrate-one.sh APP` sequentially. Protect each original PVC with Helm
   keep and each source PV with Retain. Reject other active consumers, stop the
   workload, and require its old pod to be gone before creating the copy Job.
3. Copy every source tree, preserving ownership/metadata and WAL/SHM files.
   SHA256 every regular source file against the target before SQLite checks.
   Open only target SQLite files with read-only connections for quick_check.
4. Scrutiny's copy Job additionally uses the same pinned omnibus image to run
   `influxd inspect verify-tsm`, `verify-wal` and `verify-seriesfile` against its
   copied engine. The whole omnibus workload must be stopped during this step.
   Bolt metadata is additionally validated by an isolated restored-engine startup
   and readiness check after NAS backup; file checksums alone aren't a Bolt test.
5. Apply app changes through the Fleet-native helper, preserving repo ownership.
   Wait until ALL target claim references and one desired replica arrive, then
   check rollout, Fleet, endpoints, replicas and NAS backups. A failed copy/check
   restores the source replica count without installing the target mount.

Scrutiny uses host `/run/udev` and privileged SMART collection; its new explicit
nodeSelector retains **proxmox3**, the original host. This preserves hardware
scope. Storage migration alone does not make its collector portable. Its config
and InfluxDB claims move together. Audiobookshelf NFS media stays unchanged.

## Rollback

Stop the new writer and wait for its pod to exit. Restore original Fleet claim
settings from the recorded repository definitions and reapply via Fleet. Confirm
all original mounts before starting one instance; decide explicitly how to
handle changes since cutover. Never run old/new writers concurrently or copy a
running database over another copy. Retained source data is historical rollback
state, not current live data.

See RESULTS.md for exact live results, backups and restore limitations.
