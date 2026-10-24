# Current app storage summary — 2026-10-24

Refreshed from live PVCs, Deployments/StatefulSets and Longhorn node/volume
objects after the Calibre group/Profilarr/Radarr batch. Proposed sizes come from the conservative
[measured inventory](local-pvc-usage-2026-10-24.csv) and assessment, not a new
measurement of remaining app data. Re-measure each source before migrating.
The latest batch was applied and validated; see the migration evidence below.

## On Longhorn

Twenty-three migrated apps use **30 RWO PVCs**, all configured with **two storage
replicas**. Total PVC requests are **12Gi**, approximately 12Gi of nominal replica
scheduling per node / 24Gi aggregate, excluding older tests. Requests are not
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

Homer-test was already on a separate **10Mi Longhorn RWX** claim with two app
replicas. A separate 10Mi native-restore test claim also remains. These are tests,
not production migration capacity or evidence of safe shared database writers.

Access modes describe the **PVC**, not a guarantee of concurrent-writer safety:
RWO allows mounting on one node (potentially several co-located pods); RWX allows
mounting from multiple nodes. Longhorn storage replica count is independent of
these modes. The planned RWO rows do not imply shared-writer RWX compatibility.

Original local-path PVCs for all twenty-three migrated apps remain as rollback copies.
Their presence does **not** mean these apps still run on local-path. Filebot's
inactive mounts have target references prepared, although only config is in its
zero-replica Deployment template. Its initial backups completed while a temporary
helper attached the volumes; current recurring policy skips detached volumes.

## Still local: proposed Longhorn targets

All these stateful applications remain in the deferred/single-owner group.
“SQLite or similar” below includes other embedded stores and application-owned
state; server databases are identified separately. RWO recommendations concern
ownership of the data directory, not how many SQL clients can connect to a server.
No shared-writer RWX conversion is recommended for these current deployments.

| App / shared state | Current PVC mode | Planned Longhorn mode | Backend / state type | Proposed target(s) | Total GiB |
| --- | --- | --- | --- | --- | ---: |
| AdGuard Home | RWO | RWO | bbolt stats/session state, config/query logs; not SQLite | config 256Mi + data 4Gi | 4.25 |
| BookStack | RWO | RWO | MariaDB + app config/uploads | DB 1Gi + provisional config 256Mi | 1.25* |
| Docker Mailserver | RWO | RWO | Mailboxes, queues, indexes and mail-state files | data 28Gi + config/state/logs 256Mi each | 28.75 |
| Mailpile | RWO | RWO | Mail/index state + GnuPG keyring; not identified as SQLite | data 9Gi + keys 256Mi | 9.25 |
| Sonarr | RWO | RWO | SQLite confirmed | config 1Gi | 1.00 |
| youtube-dl Material | RWO | RWO | MongoDB + app/user state | MongoDB 1Gi + appdata/users 256Mi each | 1.50 |
| Zabbix | RWO | RWO | PostgreSQL 16 | PostgreSQL 18Gi | 18.00 |
| **Total remaining** | — | — | **7 apps, 15 source claims** |  | **64.00** |

*BookStack's local MariaDB claim is mounted, but its `bookstack-config` PVC is
currently **not mounted**. The config/uploads target is provisional: locate,
measure and protect current container-layer data before any migration. Merely
copying that old claim would not prove complete data preservation.

Calibre's four-claim group now runs on Longhorn and totals **1.75Gi** (three
private configs plus one shared library). Calibre, Calibre Web, Kavita and
cover-maintenance Jobs explicitly share proxmox2-old placement for shared RWO.
Maintenance resumed after verification. Future moves must stop/co-locate every
consumer together. Their books import NFS mounts remain separate.

The largest remaining requests are mailserver (28.75Gi), Zabbix (18Gi), and
Mailpile (9.25Gi): together **56Gi** of the 64Gi remaining proposal.

## Remaining migration priority

The approved Calibre group, Profilarr and Radarr batch has completed. Remaining
units are ranked by summed historical apparent data size in the
[priority plan](remaining-migration-priority-2026-10-24.md) and CSV
`remaining_size_rank`. BookStack is smallest but held until current uploads are
located/protected; Sonarr is the next independent unit. Re-measure before every
migration and apply database-specific shutdown/restore checks.

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

With two replicas on these two nodes, remaining 64Gi of requests normally means
64Gi of additional nominal scheduling on **each** node, not 32Gi each. Current
remaining nominal budgets are approximately:

| Node | Remaining nominal budget |
| --- | ---: |
| proxmox2-old | 58.36Gi |
| proxmox3 | 85.85Gi |

Latest Longhorn disk snapshot (**2026-10-24 19:50 UTC**):

| Node | Total GiB | Physically used GiB | Physically free GiB | Reserved GiB | Scheduled GiB | Nominal remaining GiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| proxmox2-old | 78.19 | 3.29 | 74.90 | 7.82 | 12.01 | 58.36 |
| proxmox3 | 97.87 | 3.24 | 94.63 | 0.00 | 12.02 | 85.85 |

Physical free is Longhorn `storageAvailable`; scheduled is `storageScheduled`.
Nominal remaining is total minus reserved minus scheduled. Both disks report
Ready/Schedulable. Assigned capacity includes older test claims; physical
allocation grows with writes and snapshots.

Thus all remaining proposed targets do not fit on the smaller node unchanged.
This is not an instruction to enlarge disks or migrate everything: keep the
staged plan, re-measure, review retention and choose a later batch explicitly.
The overall 76Gi proposal comprises 12Gi migrated plus 64Gi remaining; physical
allocation, snapshots and required free-space margins are separate constraints.
The previous administrative 55Gi migration cap remains a further admission gate.

NAS media/download trees are not included in these PVC sizes and should remain
external. Ingress/middleware-only bundles have no application PVC to migrate.
`calibre-storage` owns shared claims already counted above; maintenance/copy
Jobs are consumers, not independent copies of that capacity. Emby/Nubile remain
Docker Compose services, outside this Kubernetes PVC inventory.

## Migration evidence

- [Homer/Smokeping pilot](migrations/pilot-2026-10-24/RESULTS.md)
- [ddclient/DuckDNS/FlareSolverr](migrations/dns-proxy-2026-10-24/RESULTS.md)
- [OpenBooks/Ubooquity](migrations/books-2026-10-24/RESULTS.md)
- [Calibre group/Profilarr/Radarr](migrations/calibre-arr-2026-10-24/RESULTS.md)
- [Audiobookshelf/Scrutiny/Prowlarr](migrations/media-small-2026-10-24/RESULTS.md)
- [Bindery/Bazarr/Authelia](migrations/sqlite-next-2026-10-24/RESULTS.md)
- [Small SQLite batch](migrations/sqlite-small-2026-10-24/RESULTS.md)
- [Disabled Filebot](migrations/filebot-2026-10-24/RESULTS.md)
- [Full assessment and original database evidence](fleet-storage-migration-assessment-2026-10-24.md)
- [RWX audit](rwx-safety-audit-2026-10-24.md)
