# Migrated local-path storage reclamation — 2026-10-26

## Completed peer reclamation — 2026-10-26T17:16:42+00:00

All **11 remaining proxmox2-old source PVCs, their PV objects and host
directories have now been deleted**. Combined with the earlier proxmox3 cleanup,
all **39 inventoried migrated local-path sources** are reclaimed. Fresh cluster
inventory contains only **Mailpile's two active local-path PVCs/PVs**, both Bound.
Their directories remain present and Mailpile is Ready 1/1. No Longhorn target
or active Mailpile storage was deleted.

Trusted SSH as sup to 10.0.0.72 worked with the existing RSA identity and strict
host-key checking; peer sudo still required a password. Cleanup used the normal
**rancher.io/local-path provisioner**: exact source UID/binding/path and non-use
checks passed, then each source PV changed Retain→Delete and its PVC was deleted
with UID/resourceVersion preconditions. The provisioner removed its source
directory and PV. Operations ran sequentially, waiting for each PVC/PV deletion.
No finalizer was forced and no host sudo access was bypassed.

Read-only helpers checked that the 11 sources were ordinary, non-symlinked
directories and later proved all 11 absent, with both Mailpile paths present.
The SSH host mount inventory showed no source or nested mounts. Both temporary
inspection helpers were removed. Historical completed migration Job records
were retained; none had an active source-claim consumer.

Peer source measurements: **312,642KiB allocated (~305.31MiB)** and
**346,812KiB apparent (~338.68MiB)**. ZFS pool measurements are separate:

| rpool metric | Before | After |
| --- | ---: | ---: |
| Allocated GiB | 168.683 | 168.385 |
| Free GiB | 67.317 | 67.615 |
| Health | ONLINE | ONLINE |

Pool free increased by **319,324,160 bytes (~304.53MiB)** over the
measurement interval. Concurrent host activity means this is not an exact
exclusive deletion delta. Reclaiming local-path data frees backing-pool space;
it does not enlarge the separate Longhorn filesystem or its free-space counter.

Final validation confirmed all 11 replacements Bound, each volume healthy
with two running replicas on distinct hosts, and all eight affected app
controllers Ready 1/1. Mailpile and Mailserver also remained Ready 1/1.
Historical migration records describe source retention at the time of migration;
those reclaimed rollback directories no longer exist. Use current Longhorn
data and verified backups for recovery. See the timestamped
[major-action log](local-path-reclamation-2026-10-26.log).

The earlier results/runbook below are historical evidence, not outstanding work.
Do not rerun this completed deletion procedure.

## Mailpile capacity check — 2026-10-26

Both Longhorn disks are currently Ready and schedulable. Longhorn's latest
reported disk sample in the inspected Node objects was collected at
17:09:53–17:10:37 UTC:

| Node | Longhorn max | Longhorn available | Scheduled | Reserved |
| --- | ---: | ---: | ---: | ---: |
| proxmox2-old | 147.09GiB | 99.31GiB | 76.00GiB | 7.82GiB |
| proxmox3 | 147.09GiB | 97.05GiB | 76.01GiB | 0GiB |

The Longhorn settings are 100% storage over-provisioning and 25% minimum
available. These reported free figures are not the physical pool limit. The
latest proxmox2-old ZFS measurement recorded in the completed reclaim log was
67.615GiB physically free on a 236GiB pool; preserving the 20% pool-free floor
leaves roughly **20.4GiB** for additional physical allocation.

Mailpile's source measurement is 6,921,275,612 apparent bytes and
6,070,158,848 allocated bytes, while
its staging claims are 9GiB and 256MiB. That request fits: the existing target
reservations are already included in Longhorn's scheduled totals, and the
measured data is below the 9GiB primary claim. The staging volumes remain
detached with unknown robustness; the primary currently reports actualSize 0
and the secondary about 32MiB. As the migration handoff warns, those counters
do not prove the staging contents are empty or valid. Do not activate or
blindly reuse them; the next copy must safely clean/resynchronize staging while
the app is stopped.

**Capacity conclusion: enough space is currently reported for the planned
two-replica Mailpile data size, but this is not a go-ahead to migrate.** The
20.4GiB physical headroom above the peer's 20% pool floor is materially smaller
than Longhorn's ~99GiB displayed free space. The proxmox2-old NVMe still has a
documented failed SMART reliability state, and the prior Mailpile bulk copy
coincided with repeated etcd/API outages. Address the peer drive reliability
issue, confirm stable control-plane operation under expected I/O, and refresh
capacity/replica/backup checks before retrying. Reclaiming the 11 local-path
sources freed only about 0.30GiB from that host pool; it did not expand
Longhorn's filesystem or remove the existing Mailpile target reservations.

## Result at 17:50 CET

The user authorized removing migrated local-path claims that are no longer in
use and have Longhorn replacements. The inventory found 39 such source PVCs:
28 on proxmox3 and 11 on proxmox2-old. Mailpile's two local-path claims remain
in use and were excluded.

On proxmox3, the 28 old data directories, PVCs and Retain PV objects were
removed. The source directories totaled **8,865,227 KiB (~8.46GiB) apparent
usage**. ZFS `rpool` reported 155GiB allocated / 317GiB free before cleanup and
146GiB allocated / 326GiB free afterward. The pool values are rounded; this is
not an exact allocation delta. Mailserver remained Ready 1/1, and Longhorn
applications continue using their target claims.

The removed claims were AdGuard Home (2), Bazarr, Bindery, BookStack (2),
Cleanuparr, ddclient, DuckDNS, Filebot (3), FlareSolverr, Homer (2),
Jellyseerr, Profilarr, Prowlarr, Radarr, Scrutiny (2), SmokePing (2), Sonarr,
youtube-dl Material (3), and Zabbix. Each source PV was node-pinned to proxmox3;
its exact host path was checked as an ordinary non-mounted directory, and the
matching Longhorn claim existed. The active Deployment/StatefulSet templates
used Longhorn claims. Longhorn volumes were healthy with two replicas except
Filebot's three detached targets; Filebot's completed migration record reports
verified copy checks and completed NAS backups. Three completed migration Job
pods (Bazarr, Filebot and Scrutiny) were removed because PVC-protection
finalizers held their source claims. Migration results remain recorded in
their respective `longhorn/migrations/*/RESULTS.md` files.

## Peer claims outstanding at 17:50 CET — now completed

The following eleven sources remained at 17:50 CET and are now deleted:

- Audiobookshelf: `audiobookshelf-config`, `audiobookshelf-metadata`
- Authelia: `authelia-config`
- Calibre group: `calibre-config`, `calibre-library`, `calibre-web-config`, `kavita-config`
- OpenBooks: `openbooks-books`, `openbooks-logs`
- Ubooquity: `ubooquity-config`
- Uptime Kuma: `uptime-kuma-config`

At 17:50 CET these original PVs were still Bound to local-path directories on
proxmox2-old and none had been changed. Later, strict host-key-verified SSH as
`sup` became available and the 11 sources were reclaimed sequentially through
the local-path provisioner. The exact source PVC UID, PV binding and path were
checked; the PV reclaim policy was changed from Retain to Delete, then the PVC
was deleted with UID/resourceVersion preconditions. The provisioner removed
the source path and PV. No finalizer was forced and no host sudo access was
bypassed. See the completed-operation log above for per-object timestamps.

Mailpile's two source claims (`mailpile-path1`, `mailpile-path2`) are still
mounted by the running Mailpile Deployment and were deliberately left alone.
