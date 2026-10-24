# Current app storage summary — 2026-10-24

Refreshed from live PVCs, Deployments/StatefulSets and Longhorn node/volume
objects after the four migrations. Proposed sizes come from the conservative
[measured inventory](local-pvc-usage-2026-10-24.csv) and assessment, not a new
measurement of remaining app data. Re-measure each source before migrating.
No cluster state was changed by this summary.

## On Longhorn

Nine migrated apps use **13 RWO PVCs**, all configured with **two storage
replicas**. Total PVC requests are **4Gi**, approximately 4Gi of nominal replica
scheduling per node / 8Gi aggregate, excluding older tests. Requests are not
physical bytes used. All active migrated workloads have one application replica.

| App | Longhorn claims / total request | State and write constraints |
| --- | --- | --- |
| Homer | config 256Mi | Running; editor/copy writes coordinated |
| Homer-without-auth | config 256Mi | Running; separate claim, co-located with Homer/copy Jobs |
| Smokeping | config 256Mi + data 256Mi = 512Mi | Running; one RRD writer |
| ddclient | config 256Mi | Running; one DNS updater |
| DuckDNS | config 256Mi | Running; one DNS updater |
| FlareSolverr | config 256Mi | Running; browser sessions process-local |
| OpenBooks | books 1Gi + logs 256Mi = 1.25Gi | Running; one instance |
| Ubooquity | config 256Mi | Running; embedded database, single owner; books stay NAS |
| Filebot | config/output/watch 256Mi each = 768Mi | Disabled (replicas=0); output/watch disabled; unused targets preserved |

Homer-test was already on a separate **10Mi Longhorn RWX** claim with two app
replicas. A separate 10Mi native-restore test claim also remains. These are tests,
not production migration capacity or evidence of safe shared database writers.

Original local-path PVCs for all nine migrated apps remain as rollback copies.
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

| App / shared state | Backend / state type | Proposed target(s) | Total GiB |
| --- | --- | --- | ---: |
| AdGuard Home | bbolt stats/session state, config/query logs; not SQLite | config 256Mi + data 4Gi | 4.25 |
| Audiobookshelf | SQLite + metadata/covers | config 256Mi + metadata 1Gi | 1.25 |
| Authelia | SQLite explicitly configured; memory sessions | config 256Mi | 0.25 |
| Bazarr | SQLite confirmed | config 256Mi | 0.25 |
| Bindery | SQLite/WAL per upstream; private config | config 256Mi | 0.25 |
| BookStack | MariaDB + app config/uploads | DB 1Gi + provisional config 256Mi | 1.25* |
| Calibre | Private config; uses shared SQLite library below | private config 256Mi | 0.25 |
| Calibre Web | SQLite private config; reads shared library | private config 256Mi | 0.25 |
| Kavita | SQLite private config; reads shared library | private config 256Mi | 0.25 |
| Shared Calibre library | SQLite metadata.db + library files | library 1Gi, counted once | 1.00 |
| Cleanuparr | SQLite: app/users/events | config 256Mi | 0.25 |
| Docker Mailserver | Mailboxes, queues, indexes and mail-state files | data 28Gi + config/state/logs 256Mi each | 28.75 |
| Jellyseerr | SQLite, WAL/SHM files observed | config 256Mi | 0.25 |
| Mailpile | Mail/index state + GnuPG keyring; not identified as SQLite | data 9Gi + keys 256Mi | 9.25 |
| Profilarr | SQLite confirmed | config 1Gi | 1.00 |
| Prowlarr | SQLite confirmed | config 256Mi | 0.25 |
| Radarr | SQLite confirmed | config 1Gi | 1.00 |
| Scrutiny | InfluxDB + embedded/config state (omnibus) | config 256Mi + InfluxDB 1Gi | 1.25 |
| Sonarr | SQLite confirmed | config 1Gi | 1.00 |
| Uptime Kuma | SQLite confirmed, installed v1 | config 256Mi | 0.25 |
| youtube-dl Material | MongoDB + app/user state | MongoDB 1Gi + appdata/users 256Mi each | 1.50 |
| Zabbix | PostgreSQL 16 | PostgreSQL 18Gi | 18.00 |
| **Total remaining** | **21 apps + one shared library, 32 source claims** | | **72.00** |

*BookStack's local MariaDB claim is mounted, but its `bookstack-config` PVC is
currently **not mounted**. The config/uploads target is provisional: locate,
measure and protect current container-layer data before any migration. Merely
copying that old claim would not prove complete data preservation.

Calibre's four-claim group totals **1.75Gi** (three private configs plus one
shared library). Calibre, Calibre Web, Kavita and cover-maintenance Jobs require
coordinated writer shutdown and explicit same-node placement for shared RWO.
Their books import NFS mounts remain separate from the shared PVC library.

The largest remaining requests are mailserver (28.75Gi), Zabbix (18Gi), and
Mailpile (9.25Gi): together **56Gi** of the 72Gi remaining proposal.

## Capacity and scope

With two replicas on these two nodes, remaining 72Gi of requests normally means
72Gi of additional nominal scheduling on **each** node, not 36Gi each. Current
remaining nominal budgets are approximately:

| Node | Remaining nominal budget |
| --- | ---: |
| proxmox2-old | 66.36Gi |
| proxmox3 | 93.85Gi |

Thus all remaining proposed targets do not fit on the smaller node unchanged.
This is not an instruction to enlarge disks or migrate everything: keep the
staged plan, re-measure, review retention and choose a later batch explicitly.
The overall 76Gi proposal comprises 4Gi migrated plus 72Gi remaining; physical
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
- [Disabled Filebot](migrations/filebot-2026-10-24/RESULTS.md)
- [Full assessment and original database evidence](fleet-storage-migration-assessment-2026-10-24.md)
- [RWX audit](rwx-safety-audit-2026-10-24.md)
