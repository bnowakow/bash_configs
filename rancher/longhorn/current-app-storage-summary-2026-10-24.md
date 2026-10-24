# Current app storage summary — 2026-10-24

Refreshed from live PVCs, Deployments/StatefulSets and Longhorn node/volume
objects after the Audiobookshelf/Scrutiny/Prowlarr batch. Proposed sizes come from the conservative
[measured inventory](local-pvc-usage-2026-10-24.csv) and assessment, not a new
measurement of remaining app data. Re-measure each source before migrating.
The latest batch was applied and validated; see the migration evidence below.

## On Longhorn

Eighteen migrated apps use **24 RWO PVCs**, all configured with **two storage
replicas**. Total PVC requests are **8.25Gi**, approximately 8.25Gi of nominal replica
scheduling per node / 16.5Gi aggregate, excluding older tests. Requests are not
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

Homer-test was already on a separate **10Mi Longhorn RWX** claim with two app
replicas. A separate 10Mi native-restore test claim also remains. These are tests,
not production migration capacity or evidence of safe shared database writers.

Access modes describe the **PVC**, not a guarantee of concurrent-writer safety:
RWO allows mounting on one node (potentially several co-located pods); RWX allows
mounting from multiple nodes. Longhorn storage replica count is independent of
these modes. The planned RWO rows do not imply shared-writer RWX compatibility.

Original local-path PVCs for all eighteen migrated apps remain as rollback copies.
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
| Calibre | RWO | RWO | Private config; uses shared SQLite library below | private config 256Mi | 0.25 |
| Calibre Web | RWO | RWO | SQLite private config; reads shared library | private config 256Mi | 0.25 |
| Kavita | RWO | RWO | SQLite private config; reads shared library | private config 256Mi | 0.25 |
| Shared Calibre library | RWO | RWO | SQLite metadata.db + library files | library 1Gi, counted once | 1.00 |
| Docker Mailserver | RWO | RWO | Mailboxes, queues, indexes and mail-state files | data 28Gi + config/state/logs 256Mi each | 28.75 |
| Mailpile | RWO | RWO | Mail/index state + GnuPG keyring; not identified as SQLite | data 9Gi + keys 256Mi | 9.25 |
| Profilarr | RWO | RWO | SQLite confirmed | config 1Gi | 1.00 |
| Radarr | RWO | RWO | SQLite confirmed | config 1Gi | 1.00 |
| Sonarr | RWO | RWO | SQLite confirmed | config 1Gi | 1.00 |
| youtube-dl Material | RWO | RWO | MongoDB + app/user state | MongoDB 1Gi + appdata/users 256Mi each | 1.50 |
| Zabbix | RWO | RWO | PostgreSQL 16 | PostgreSQL 18Gi | 18.00 |
| **Total remaining** | — | — | **12 apps + one shared library, 21 source claims** |  | **67.75** |

*BookStack's local MariaDB claim is mounted, but its `bookstack-config` PVC is
currently **not mounted**. The config/uploads target is provisional: locate,
measure and protect current container-layer data before any migration. Merely
copying that old claim would not prove complete data preservation.

Calibre's four-claim group totals **1.75Gi** (three private configs plus one
shared library). Calibre, Calibre Web, Kavita and cover-maintenance Jobs require
coordinated writer shutdown and explicit same-node placement for shared RWO.
Their books import NFS mounts remain separate from the shared PVC library.

The largest remaining requests are mailserver (28.75Gi), Zabbix (18Gi), and
Mailpile (9.25Gi): together **56Gi** of the 67.75Gi remaining proposal.

## Remaining migration priority

User confirmed the Bindery/Bazarr/Authelia batch works. The next approved
size-ranked batch (Audiobookshelf/Scrutiny/Prowlarr) is now migrated.
Remaining units are prioritized by summed **measured apparent data size**,
keeping dependent claims together; see the [ranked plan](remaining-migration-priority-2026-10-24.md).
The smallest remaining complete unit is the Calibre/Calibre Web/Kavita/shared
library group (1.75Gi). BookStack follows by measured size but remains blocked
on locating current uploads; Profilarr follows after that. Re-measure before
execution and retain the shared-library ownership/placement constraints.

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

With two replicas on these two nodes, remaining 67.75Gi of requests normally means
67.75Gi of additional nominal scheduling on **each** node, not 33.875Gi each. Current
remaining nominal budgets are approximately:

| Node | Remaining nominal budget |
| --- | ---: |
| proxmox2-old | 62.11Gi |
| proxmox3 | 89.60Gi |

Thus all remaining proposed targets do not fit on the smaller node unchanged.
This is not an instruction to enlarge disks or migrate everything: keep the
staged plan, re-measure, review retention and choose a later batch explicitly.
The overall 76Gi proposal comprises 8.25Gi migrated plus 67.75Gi remaining; physical
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
- [Audiobookshelf/Scrutiny/Prowlarr](migrations/media-small-2026-10-24/RESULTS.md)
- [Bindery/Bazarr/Authelia](migrations/sqlite-next-2026-10-24/RESULTS.md)
- [Small SQLite batch](migrations/sqlite-small-2026-10-24/RESULTS.md)
- [Disabled Filebot](migrations/filebot-2026-10-24/RESULTS.md)
- [Full assessment and original database evidence](fleet-storage-migration-assessment-2026-10-24.md)
- [RWX audit](rwx-safety-audit-2026-10-24.md)
