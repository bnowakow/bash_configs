# Sonarr, youtube-dl Material and AdGuard Home results — 2026-10-24/25

Completed and applied through Fleet. Sonarr, youtube-dl Material and AdGuard
Home now use six Longhorn RWO claims with two healthy storage replicas on
separate hosts (proxmox2-old/proxmox3). All four Deployments (including MongoDB)
have one available replica and Recreate strategy. All four changed Fleet bundles
report 1/1 BundleDeployments ready. Images, credentials, DNS services and NFS
media mounts are preserved; only state claims/ownership strategy and AdGuard's
explicit original-host placement changed.

| Source retained | New claim | Request | Regular files SHA256 verified | Engine checks before cutover |
| --- | --- | ---: | ---: | --- |
| sonarr-config | sonarr-config-longhorn-rwo | 1Gi | 2433 | sonarr.db + logs.db SQLite quick_check: OK |
| youtubedl-material-appdata | youtubedl-material-appdata-longhorn-rwo | 256Mi | 12 | Copied with MongoDB/users; checksums matched |
| youtubedl-material-users | youtubedl-material-users-longhorn-rwo | 256Mi | 0 | Source directory empty; preserved |
| youtubedl-material-mongodb-data | youtubedl-material-mongodb-data-longhorn-rwo | 1Gi | 403 | MongoDB full validation: 16 collections, four DBs |
| adguard-home-config | adguard-home-config-longhorn-rwo | 256Mi | 1 | Full config checksum matched |
| adguard-home-data | adguard-home-data-longhorn-rwo | 4Gi | 15 | bbolt stats.db + sessions.db: OK |

Every source writer was stopped and its pod gone before copying; MongoDB was
stopped after its app. All complete trees, ownership/metadata and any WAL/SHM
sidecars were preserved. Every regular file matched SHA256 before target engine
checks. Sources stayed read-only in copy/measurement Jobs. Original local PVCs
remain Bound with Helm keep annotations, and original PVs use Retain. No source
repair/checkpoint or data-volume deletion was performed.

## Source sizing and space interpretation

| Source | Allocated bytes | Apparent bytes | Measurement |
| --- | ---: | ---: | --- |
| Sonarr config | 420487168 | 737885476 | 2026-10-24 preflight |
| youtube-dl Material appdata | 3202560 | 3936739 | 2026-10-24 preflight |
| youtube-dl Material users | 0 | 0 | 2026-10-24 preflight |
| MongoDB data | 524422656 | 740897674 | 2026-10-24 preflight |
| AdGuard config | 4608 | 5736 | 2026-10-25 remeasurement |
| AdGuard data | 840532480 | 3229208658 | 2026-10-25 remeasurement |

AdGuard used GNU cp `--sparse=always`. Source allocated blocks reflect filesystem
sparsity/compression and need not equal ext4 allocation inside Longhorn. Live
target `du -sk` reported 3152900KiB for AdGuard work data (~3.01GiB), within its
4Gi claim. This is not physical per-host Longhorn usage; snapshots, replicas and
backend filesystem allocation differ. Quotas were based on apparent size plus
buffer. No quota or disk enlargement was needed during this batch.

## Initial outage and guarded retry

The first attempt stopped at preflight because k3s restarted and etcd/API
readiness failed. Unfinished app definitions were restored/staged outside Fleet;
no app was switched then. HANDOFF.md preserves that incident and another root
session's diagnosis. On resume both nodes were Ready, etcd had a leader and API
readiness passed. The observed local WAL fsync interval averaged ~2ms, with
NRestarts=8 unchanged throughout resumed execution, overnight and final checks.
This migration did not reset etcd, change service/firewall/membership settings
or establish that the original cause was permanently fixed.

The first isolated MongoDB checker exited before validation while using the
image default UID. Cutover was blocked and original MongoDB/app replicas were
restored. Its failed-Job evidence was saved in /tmp. The checker was corrected
to production UID 568/GID 0; only failed derived target copies were cleared and
all three states re-copied after another full writer shutdown. The retry passed
full collection validation using the exact MongoDB 9.0.4 image. No repair or
private record query was used. Expected app DB presence was checked.

MongoDB was made Ready on target while the app remained at replicas=0. Only
then was the app applied at one replica. Opaque app/MongoDB Secret data matched
before/after. The app took several minutes to initialize and refresh its
existing downloader binary, then stayed Ready. An initial render comparison
normalized Kubernetes's omitted empty environment values; effective env/secret
references, pinned images and NAS volumes matched their originals.

## AdGuard and DNS

Both hosts' pre-Tailscale resolvers were independent public resolvers (8.8.8.8
on proxmox3, 1.1.1.1 on proxmox2-old). Host probes, public DNS and an in-cluster
FQDN probe resolved the NAS/registry. The cluster probe also succeeded while
AdGuard was stopped. Absolute FQDNs with trailing dots avoid search-suffix
ambiguity seen in an earlier probe. No resolver settings were changed.

The bbolt 1.4.3 CLI was built/cached before downtime. AdGuard's config and data
moved together, with both target bbolt files checked offline. The workload
retains proxmox3 placement for this cutover. LoadBalancer DNS Services retain
both 10.0.0.50 and 10.0.0.72 addresses and original ports/protocols.

After startup, UDP A queries for example.org and TCP A queries for the NAS
succeeded through **both node IPs**; NAS resolved to 10.0.0.20. Both HTTPS hosts
for each app passed certificate-verified HTTP 200 checks (Sonarr `/ping`,
youtube-dl Material `/`, AdGuard `/`). Recent 150-line logs for all four
workloads showed none of the checked SQLite corruption/locked/read-only,
permission-denied, WT_PANIC, authentication-failed or checksum-mismatch markers.

Authenticated app workflows, actual Sonarr grabs/downloads, youtube-dl Material
media downloads and AdGuard filtering-rule/account changes were not exercised.
Please test normal user workflows before retiring historical rollback copies.

## NAS backups and representative restores

Native Job `longhorn-system/sya-nas-backup-20261025` completed at
**2026-10-25T06:56:52Z**. All six fresh backups report Completed
and were created after this manual run started:

| Claim | Longhorn volume | Backup |
| --- | --- | --- |
| sonarr-config-longhorn-rwo | pvc-a92b6dd1-073c-4142-9bac-6d133a429b1c | backup-c8854e0e3141484e |
| youtubedl-material-appdata-longhorn-rwo | pvc-3d1d3369-7191-48cb-8b12-cbe919c23084 | backup-c4424ee783564ca4 |
| youtubedl-material-users-longhorn-rwo | pvc-aa730249-f948-4e36-9fbe-3e9afee6656d | backup-e1419d149bf04353 |
| youtubedl-material-mongodb-data-longhorn-rwo | pvc-4d1b252e-d46a-41b3-9319-757c806491d1 | backup-00133492fcd541a6 |
| adguard-home-config-longhorn-rwo | pvc-0e8f2e61-fa83-4fad-91d2-0e3f190562ad | backup-f3de5e5179f8432d |
| adguard-home-data-longhorn-rwo | pvc-700725ab-ad4b-4f5d-b457-e9ac35221d22 | backup-2c6bab3f62944571 |

The MongoDB data backup and both AdGuard backups were restored into isolated
scratch RWO volumes (1Gi + 256Mi + 4Gi). The same pinned MongoDB binary, bound
only to localhost without a Service, passed full validation of **16 collections
across four databases**. The restored AdGuard config was present and both bbolt
files passed `bbolt check`. No production mounts or application/collector
processes were used by the restore Job; MongoDB stopped cleanly afterward.

The three scratch claims/Delete-policy StorageClasses, restore Job, measurement,
image-cache/DNS/tooling Jobs, DNS probe Pod and local tooling PVC were removed
after success. Migration copy Jobs and native backup Job remain as evidence. The completed
AdGuard copy Pod was removed after its log/Job metadata were saved under /tmp
to release the temporary tooling PVC protection; its verification results are
recorded above.
Sonarr and the youtube-dl Material appdata/users backups were not independently
restore-tested. The recurring daily NAS group retains 14 backups. These are live,
separately captured volume snapshots, not atomic/quiesced multi-volume backups;
the representative restored engine states passed, but future cross-volume
consistency-sensitive work still requires app-aware coordination.

## Capacity, documentation and validation

This batch adds **6.75Gi per host / 13.5Gi aggregate nominal replica capacity**.
Production migrations total **26 apps, 36 RWO claims and 18.75Gi requested**
(**37.5Gi aggregate replicas**). Remaining proposals total **57.25Gi/9 claims
across four apps**. Nominal remaining budgets are approximately **51.61Gi on
proxmox2-old / 79.10Gi on proxmox3**. Physical allocation/snapshots/free-space
thresholds are separate. No default StorageClass or disk sizes changed.

Updated the [app summary](../../current-app-storage-summary-2026-10-24.md),
[assessment](../../fleet-storage-migration-assessment-2026-10-24.md), CSV completion
markers and [remaining size ranks](../../remaining-migration-priority-2026-10-24.md).
Historical measurements/outage notes remain preserved. Bash/POSIX syntax,
ShellCheck, render invariants, retry-cleanup/SQLite-WAL fixture (source bytes
unchanged) and whitespace checks passed. No commit or push was made.
See [procedure and rollback](README.md).
