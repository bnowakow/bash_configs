# Current app storage summary — 2026-10-24

**Mailpile completed — 2026-10-28T18:41:14+00:00:** Mailpile runs on12Gi data +256Mi keys, RWO/two healthy replicas. All52 maintenance targets are restored to Fleet desired state and Ready where applicable. Live inventory: **46 Bound Longhorn claims /79.259765625Gi requested**, including idle retained/test claims. BookStack config is now512Mi (online expansion after a full-filesystem startup failure). CloudCasa has one documented unchanged pre-existing template-drift exception; its agent is Ready. See [migration results](migrations/mailpile-2026-10-26/RESULTS.md) and [restoration report](migrations/mailpile-2026-10-26/RESTORATION.json). Original Mailpile local claims remain unused rollback copies.









**Mailpile preparation update — 2026-10-26:** source growth to 9.41GiB logical
requires a 12Gi data target plus 256Mi keys (12.25Gi total), still RWO/two replicas.
That storage request was applied; final expansion/health could not be verified
because APIs/k3s became unstable. No Mailpile shutdown, data copy or app cutover
occurred. It remains on original local claims; an idle transfer helper's cleanup
is unconfirmed. See the [current handoff](migrations/mailpile-2026-10-26/HANDOFF.md).
The old 9.25Gi staging size below describes the preceding attempt; production
completion totals must not include this unverified new attempt.


**Reclamation update — 2026-10-26:** all 39 inventoried unused migrated
local-path source PVCs/PVs and directories have been removed (28 on proxmox3,
11 on proxmox2-old). Only Mailpile's two active local-path claims remain.
Longhorn targets remain healthy; original local source copies are no longer
available for rollback. See the [reclamation record](local-path-reclamation-2026-10-26.md).


**Restoration update — 2026-10-25 20:14 UTC:** all 30 application controllers
temporarily stopped for I/O relief have returned to their intended ready counts;
Filebot remains disabled. The five production replica exceptions recovered
through normal reattachment. Both APIs passed and both hosts' current I/O PSI
was zero. See the [restoration record](io-pressure-incident-2026-10-25.md#applications-restored--2026-10-25-2114-cet--2014-utc)
and [action log](application-restoration-2026-10-25.log). Historical capacity
snapshots and the peer's hardware reliability finding remain separate concerns.

**Runtime/maintenance update — 2026-10-25 approximately 19:05 UTC:** VM 700 and
601 successfully migrated to proxmox5, releasing approximately **33.86GiB** of
source disk allocation. Local NVMe pool free is now **84.79GiB**, with **37.59GiB
headroom above a 20% pool-free margin**. Both VMs remain stopped. The Longhorn
150GiB backing size is unchanged. See the [migration record](io-pressure-incident-2026-10-25.md).

**Earlier maintenance update — 2026-10-25 18:36 UTC:** nonessential applications
were deliberately scaled down for the [I/O incident](io-pressure-incident-2026-10-25.md)
at that timestamp; the later restoration update above supersedes that hold.
The app rows below describe migrated storage ownership, not current availability.
Both backing zvols are now **150GiB** (proxmox3: 100 → 150GiB; proxmox2-old:
80 → 150GiB); ext4/Longhorn capacity is **147.09GiB per host**. Proxmox2-old's
SMART reliability warning remains. See the expansion logs for
[proxmox3](proxmox3-expansion-2026-10-25.log) and
[proxmox2-old](proxmox2-old-expansion-2026-10-25.log).

Refreshed from live PVCs, Deployments/StatefulSets and Longhorn node/volume
objects after the BookStack migration (2026-10-25). Proposed sizes come from the conservative
[measured inventory](local-pvc-usage-2026-10-24.csv) and assessment, not a new
measurement of remaining app data. Re-measure each source before migrating.
The latest batch was applied and validated; see the migration evidence below.

## On Longhorn

Twenty-eight migrated apps use **39 RWO PVCs**, all configured with **two storage
replicas**. Total PVC requests are **38Gi**, approximately 38Gi of nominal replica
scheduling per node / 76Gi aggregate, excluding older tests. Requests are not
physical bytes used. All active migrated workloads have one application replica.

| App | PVC mode | Longhorn claims / total request | State and write constraints |
| --- | --- | --- | --- |
| Homer | RWO | config 256Mi | Running; editor/copy writes coordinated |
| Homer-without-auth | RWO | config 256Mi | Running; separate claim, co-located with Homer/copy Jobs |
| Smokeping | RWO | config 256Mi + data 256Mi = 512Mi | Running; one RRD writer |
| ddclient | RWO | config 256Mi | Running; one DNS updater |
| DuckDNS | RWO | config 256Mi | Running; one DNS updater |
| FlareSolverr | RWO | config 256Mi | Running; browser sessions process-local |
| OpenBooks | RWO | books 1Gi + logs 256Mi = 1.25Gi | Running; one instance |
| Ubooquity | RWO | config 256Mi | Running; embedded database, single owner; books stay NAS |
| Filebot | RWO | config/output/watch 256Mi each = 768Mi | Disabled (replicas=0); output/watch disabled; unused targets preserved |
| Jellyseerr | RWO | config 256Mi | Running; SQLite, one writer, Recreate |
| Cleanuparr | RWO | config 256Mi | Running; three SQLite databases, one writer, Recreate |
| Uptime Kuma | RWO | config 256Mi | Running; SQLite, one scheduler, Recreate |
| Bindery | RWO | config 256Mi | Running; SQLite, one writer, Recreate; media stays NAS |
| Bazarr | RWO | config 256Mi | Running; SQLite, one writer, Recreate; media stays NAS |
| Authelia | RWO | config 256Mi | Running; SQLite, one writer, Recreate; existing secrets retained |
| Audiobookshelf | RWO | config 256Mi + metadata 1Gi = 1.25Gi | Running; SQLite, one instance, Recreate; media stays NAS |
| Scrutiny | RWO | config 256Mi + InfluxDB 1Gi = 1.25Gi | Running; one omnibus instance, Recreate, retained proxmox3 hardware scope |
| Prowlarr | RWO | config 256Mi | Running; SQLite, one writer, Recreate |
| Calibre | RWO | config 256Mi | Running; Recreate, writable shared library, proxmox2-old |
| Calibre Web | RWO | config 256Mi | Running; Recreate, shared library read-only, proxmox2-old |
| Kavita | RWO | config 256Mi | Running; Recreate, shared library read-only, proxmox2-old |
| Shared Calibre library (counted once) | RWO | library 1Gi | Calibre + maintenance writes coordinated; all consumers on proxmox2-old |
| Profilarr | RWO | config 1Gi | Running; SQLite, one writer, Recreate |
| Radarr | RWO | config 1Gi | Running; SQLite, one writer, Recreate; media stays NAS |
| Sonarr | RWO | config 1Gi | Running; SQLite, one writer, Recreate; media stays NAS |
| youtube-dl Material | RWO | appdata/users 256Mi each + MongoDB 1Gi = 1.5Gi | Running; app and MongoDB each singleton/Recreate; media stays NAS |
| AdGuard Home | RWO | config 256Mi + data 4Gi = 4.25Gi | Running; bbolt single owner, Recreate, retained proxmox3 placement |

| Zabbix | RWO | PostgreSQL 18Gi | Running; PostgreSQL 16.15, single database owner, native backup/recovery verified |

| BookStack | RWO | config 512Mi + MariaDB 1Gi = 1.5Gi | Running; live container config preserved, one app/database owner, Recreate; original encryption key explicitly retained |

Homer-test was already on a separate **10Mi Longhorn RWX** claim with two app
replicas. A separate 10Mi native-restore test claim also remains. These are tests,
not production migration capacity or evidence of safe shared database writers.

Access modes describe the **PVC**, not a guarantee of concurrent-writer safety:
RWO allows mounting on one node (potentially several co-located pods); RWX allows
mounting from multiple nodes. Longhorn storage replica count is independent of
these modes. The planned RWO rows do not imply shared-writer RWX compatibility.

Unused migrated local-path source PVCs/PVs and directories have been reclaimed;
see the reclamation update above. BookStack's old config PVC was unmounted; its
actual live config was preserved in a private archive and its Longhorn claim. Filebot's
inactive mounts have target references prepared, although only config is in its
zero-replica Deployment template. Its initial backups completed while a temporary
helper attached the volumes; current recurring policy skips detached volumes.

## Mailpile staging allocation — not migrated

The attempted Mailpile copy was interrupted by recurring control-plane failures.
Mailpile was restored to original local storage with one available replica and
HTTPS 200. Two unverified Longhorn target claims reserve **9.25Gi per host**;
they are not included in the 28 migrated apps/39 production claims/38Gi above.
No Mailpile completion marker was added. See the [incident handoff](migrations/mailpile-2026-10-25/HANDOFF.md).

## Still local: proposed Longhorn targets

All these stateful applications remain in the deferred/single-owner group.
“SQLite or similar” below includes other embedded stores and application-owned
state; server databases are identified separately. RWO recommendations concern
ownership of the data directory, not how many SQL clients can connect to a server.
No shared-writer RWX conversion is recommended for these current deployments.

| App / shared state | Current PVC mode | Planned Longhorn mode | Backend / state type | Proposed target(s) | Total GiB |
| --- | --- | --- | --- | --- | ---: |
| Docker Mailserver | RWO | RWO | Mailboxes, queues, indexes and mail-state files | data 28Gi + config/state/logs 256Mi each | 28.75 |
| Mailpile | RWO | RWO | Mail/index state + GnuPG keyring; not identified as SQLite | data 9Gi + keys 256Mi | 9.25 |
| **Total remaining** | — | — | **2 apps, 6 source claims** |  | **38.00** |

Calibre's four-claim group now runs on Longhorn and totals **1.75Gi** (three
private configs plus one shared library). Calibre, Calibre Web, Kavita and
cover-maintenance Jobs explicitly share proxmox2-old placement for shared RWO.
Maintenance resumed after verification. Future moves must stop/co-locate every
consumer together. Their books import NFS mounts remain separate.

The largest remaining requests are Docker Mailserver (28.75Gi) and Mailpile
(9.25Gi).

## Remaining migration priority

BookStack is complete; see [execution evidence](migrations/bookstack-2026-10-25/RESULTS.md).
Its live container-layer files were located, preserved, mounted persistently,
and verified alongside MariaDB, resolving the earlier uploads/config blocker.
**Keep Mailpile last by user decision.** Docker Mailserver is the next independent
candidate, but its 28.75Gi proposal exceeds current smaller-node nominal capacity
and the existing 55Gi migration cap when added to production. Re-measure and
review capacity before authorizing another stage. See the
[remaining plan](remaining-migration-priority-2026-10-24.md).

## Other storage types retained

These mounts are external NAS NFS volumes, not Longhorn PVCs. Their Kubernetes
PVC access mode is **N/A**; application permissions/read-only flags still apply.
They are excluded from the proposed Longhorn sizes.

| Apps | Additional storage type / purpose |
| --- | --- |
| Audiobookshelf | NFS: audiobooks and children's audiobooks |
| Bazarr, Bindery, Radarr, Sonarr | NFS: shared media/download tree |
| Calibre, Calibre Web, Kavita, Ubooquity | NFS: books/import tree |
| Filebot | NFS: `/storage` media tree; app remains disabled |
| youtube-dl Material | NFS: audio, subscriptions and video |

Calibre Web and Kavita also read the shared Calibre **RWO PVC** read-only; that
mount is not RWX or NFS. Homer-test and the native-restore test remain the
separate Longhorn RWX examples described above. Ingress-only bundles have no
PVC access mode, and container `emptyDir` volumes are ephemeral rather than
persistent RWO/RWX claims.

## Capacity and scope

Remaining proposals total 38Gi. Mailpile's 9.25Gi is already allocated as
unverified staging, so another **28.75Gi on each host** would be needed if that
staging is reused after a successful retry. Current nominal budgets, already
excluding the staging allocation, are approximately:

| Node | Remaining nominal budget |
| --- | ---: |
| proxmox2-old | 94.76Gi (before repairing missing/failed replica placements) |
| proxmox3 | 99.82Gi |

Latest Longhorn disk snapshots (**both: 2026-10-25 18:36:10 UTC**;
includes unverified Mailpile staging):

| Node | Filesystem total GiB | Filesystem used GiB | Filesystem free GiB | Reserved GiB | Scheduled GiB | Nominal remaining GiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| proxmox2-old | 147.09 | 21.40 | 125.68 | 7.82 | 44.51 | 94.76 |
| proxmox3 | 147.09 | 24.53 | 122.56 | 0.00 | 47.27 | 99.82 |

Filesystem free is Longhorn `storageAvailable`; scheduled is `storageScheduled`.
These filesystem figures do not represent backing-pool physical capacity.
The later direct host sample found **125.76GiB ext4 free**, including **6.84GiB
reserved free**, leaving **118.93GiB available in `df`**. The backing `rpool`
had **50.97GiB physically free / 43.67GiB shared dataset-available**; these are
separate accounting layers, not additive budgets. Only **3.77GiB** of further
physical allocation remained above the 20% pool-free planning floor **before
the VM migrations**. Current pool free/headroom is **84.79 / 37.59GiB**. See the
[ZFS/ext4 breakdown](README-4-expand-storage.md#zfs-pool-space-versus-ext4-free-space)
for the full table and reservation distinctions. These later samples do not
replace the timestamped Longhorn API snapshot above.
Nominal remaining is total minus reserved minus scheduled. Both disks report
Ready/Schedulable. Assigned capacity includes older test claims; physical
allocation grows with writes and snapshots.

At this historical snapshot, the peer's scheduled total was lower because detached
replica placements are missing/failed after the incident. Its displayed nominal
room is not an admission allowance: re-measure after replica recovery. All
attached volumes were healthy with two RW engine replicas at the resize check;
five detached production volumes lacked two nonfailed replicas. Their completed
NAS backups were checked. The local resize did not repair those exceptions.

Both hosts now have nominal room for the remaining proposed requests, but this
does not establish physical capacity or authorize migration. Proxmox2-old's
NVMe-backed pool now has **84.79GiB physically free**, with **37.59GiB above a
20% pool-free planning floor** after moving VM 700 and 601. The timestamped
Longhorn filesystem-free figure above remains sparse virtual space, not
guaranteed backing. Earlier ZFS dataset-available figures predate the VM moves
and must be re-measured. Drive reliability and physical growth/admission checks
remain outstanding. Keep the staged plan, re-measure, review retention and
choose a later batch explicitly.
The overall 76Gi proposal comprises 38Gi migrated plus 38Gi remaining; physical
allocation, snapshots and required free-space margins are separate constraints.
The previous administrative 55Gi migration cap remains a further admission gate.

NAS media/download trees are not included in these PVC sizes and should remain
external. Ingress/middleware-only bundles have no application PVC to migrate.
`calibre-storage` owns shared claims already counted above; maintenance/copy
Jobs are consumers, not independent copies of that capacity. Emby/Nubile remain
Docker Compose services, outside this Kubernetes PVC inventory.

## Migration evidence

- [BookStack](migrations/bookstack-2026-10-25/RESULTS.md)

- [Zabbix PostgreSQL](migrations/zabbix-2026-10-25/RESULTS.md)

- [Homer/Smokeping pilot](migrations/pilot-2026-10-24/RESULTS.md)
- [ddclient/DuckDNS/FlareSolverr](migrations/dns-proxy-2026-10-24/RESULTS.md)
- [OpenBooks/Ubooquity](migrations/books-2026-10-24/RESULTS.md)
- [Sonarr/youtube-dl Material/AdGuard Home](migrations/sonarr-ytdl-adguard-2026-10-24/RESULTS.md)
- [Calibre group/Profilarr/Radarr](migrations/calibre-arr-2026-10-24/RESULTS.md)
- [Audiobookshelf/Scrutiny/Prowlarr](migrations/media-small-2026-10-24/RESULTS.md)
- [Bindery/Bazarr/Authelia](migrations/sqlite-next-2026-10-24/RESULTS.md)
- [Small SQLite batch](migrations/sqlite-small-2026-10-24/RESULTS.md)
- [Disabled Filebot](migrations/filebot-2026-10-24/RESULTS.md)
- [Full assessment and original database evidence](fleet-storage-migration-assessment-2026-10-24.md)
- [RWX audit](rwx-safety-audit-2026-10-24.md)

## Host expansion target and completed local resize

See [host expansion procedure and sizing](README-4-expand-storage.md): the user
selected **150GiB per host**. Both are complete: proxmox3 100 → 150GiB;
proxmox2-old 80 → 150GiB. The second grow passed a ten-minute both-host
stability screen; all attached volumes remained healthy with two RW engine
replicas. At that time detached replica exceptions remained; the five production
exceptions recovered during the later application restoration. Sparse virtual capacity
is not guaranteed backing space. PVC sizes, replica policy and migration cap
are unchanged; no stopped applications were restored by the resize.
