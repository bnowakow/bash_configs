# OpenBooks / Ubooquity migration results — 2026-10-24

Both apps are deployed on singleton Longhorn RWO storage with Recreate strategy.
The user explicitly selected these apps. No RWX conversion or multi-writer
configuration was introduced. No other app migrated in this batch.

## Volumes and backups

All targets use `longhorn-rwo-2replicas`, ext4, Retain/keep protection and the
`nas-backup` group. Each is healthy with one running replica on proxmox2-old
and one on proxmox3. Added nominal capacity is **1.5Gi per host** (3Gi aggregate
replica capacity). All three migration batches now total **3.25Gi per host**
of application PVC requests. No disks were enlarged or default classes changed.

| App | Retained original | New target | Request | Native NAS backup |
| --- | --- | --- | --- | --- |
| `openbooks` | `openbooks-books` | `openbooks-books-longhorn-rwo` | 1Gi | `backup-357e8ff10e8f45c3` |
| `openbooks` | `openbooks-logs` | `openbooks-logs-longhorn-rwo` | 256Mi | `backup-d7238e5b6e8948f8` |
| `ubooquity` | `ubooquity-config` | `ubooquity-config-longhorn-rwo` | 256Mi | `backup-dcec7339899e4c50` |

Native job `longhorn-system/books-nas-backup-20261024` completed. The three
volumes are enrolled in the existing scheduled NAS backups; target and retention
policy were preserved. These are live-volume backups, not an asserted
application-consistent H2 export. The source copy was taken with Ubooquity
stopped. No separate restore drill or database integrity checker was run in
this batch; the first pilot's isolated native restore remains the storage-path
recovery evidence.

## Verified behavior

- Preflight found no CloudCasa helper/data-mover pods. Source data was measured
  via node/PV mappings: OpenBooks books empty, logs ~0.115Mi apparent; Ubooquity
  config ~4.8Mi allocated. OpenBooks has no shell, so no diagnostic software was
  installed in its container.
- OpenBooks stopped before both source claims were copied. Empty books were
  explicitly verified, and every regular log file passed SHA256 verification.
- Ubooquity's old pod was fully gone before its embedded database/config copy.
  Its 60-second grace needed a second bounded wait; no copy started after the
  first short timeout alone. Every copied regular file passed SHA256 checks.
- Both Deployments have one available replica and all intended target claims
  mounted. Fleet bundles `openbooks`, `ubooquity`, `longhorn-books-storage`
  reached Ready. Pinned chart versions and ingress definitions were preserved.
- OpenBooks main HTTPS hosts both returned 200.
- Ubooquity main `/ubooquity/` and admin `/ubooquity/admin` returned 200 on both
  usual HTTPS hostnames, four endpoints total.
- Strict read checks confirmed Ubooquity's existing `ubooquity-6.mv.db` and
  preferences file were present/readable. No settings contents were printed.
- Ubooquity still mounts
  `nas.localdomain.bnowakowski.pl:/mnt/PlexPool/plex/Books` at `/books`; listing
  succeeded inside the running app. NAS books were not copied into Longhorn.
- Ubooquity's target filesystem reported 5.1Mi used of about 224Mi usable,
  with about 214Mi free (3% reported use). ext4 usable capacity is smaller than
  the nominal 256Mi block request.
- All three source PVCs remain Bound with keep annotations, and source PVs use
  Retain. No source or target claims, PVs or data directories were deleted.

## Follow-up / rollback

See [README.md](README.md) for original claim names and rollback procedure.
Original runtime workload/repository definitions are in
`/tmp/longhorn-batch3-originals` during this session; do not commit private
application configuration. Original data is a cutover-time recovery point:
preserve new downloads/settings before reverting. Keep rollback PVCs until
backup/recovery and a retention interval have been reviewed.

Monitor growth, especially OpenBooks' 1Gi download volume and retained logs.
Moving downloads to NAS or changing log retention remains separate work.
Application-level authenticated browsing/download workflows and a hard node-loss
failover were not exercised. No online expansion was performed. Nothing was
committed or pushed by this operation.
