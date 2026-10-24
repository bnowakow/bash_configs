# Remaining migration priority by size — 2026-10-24

User confirmed the Audiobookshelf/Scrutiny/Prowlarr batch works. The next
approved Calibre/Calibre Web/Kavita/shared library, Profilarr and Radarr batch
has now migrated; see its [results](migrations/calibre-arr-2026-10-24/RESULTS.md).
Production migrations total **23 apps, 30 RWO claims and 12Gi requested**
(**24Gi nominal aggregate replicas**).

## Priority rule

Prioritize **ascending measured apparent source bytes summed across the complete
migration unit**, including database/metadata claims. Shared libraries and all
consumers move together; Calibre's four-claim unit is now completed. Apparent
size counts logical file lengths, including sparse files; allocated size shows
actual source filesystem blocks. Neither predicts exact Longhorn replica or
snapshot physical allocation.

Remaining measurements are historical from the original inventory around
2026-10-24 07:51 UTC. Re-measure before execution and reassess target buffer.
Size order does not override blockers, coordinated shutdown or single-owner
rules. All remaining targets are **RWO with two storage replicas**, not shared
multi-writer RWX. The CSV's `remaining_size_rank` gives each claim its unit's
rank; completed claims have a blank rank. Existing size/priority data is retained.

## Ranked remaining units

| Priority | App / migration unit | Allocated MiB | Apparent MiB | Proposed GiB per host | Aggregate replicas GiB | Conditions |
| ---: | --- | ---: | ---: | ---: | ---: | --- |
| 1 | BookStack | 22.32 | 409.86 | 1.25 | 2.5 | Held: locate/protect current container-layer config/uploads; old config PVC is unmounted |
| 2 | Sonarr | 397.27 | 698.64 | 1 | 2 | SQLite, one writer; media stays NFS |
| 3 | youtube-dl Material | 504.44 | 712.13 | 1.5 | 3 | MongoDB + app/user state; coordinate three claims |
| 4 | AdGuard Home | 786.56 | 3020.80 | 4.25 | 8.5 | bbolt single owner; coordinate DNS downtime |
| 5 | Mailpile | 5788.98 | 6600.60 | 9.25 | 18.5 | Mail/index state and GnuPG keys; two claims |
| 6 | Zabbix | 5708.23 | 13941.71 | 18 | 36 | PostgreSQL; engine-specific shutdown/restore checks |
| 7 | Docker Mailserver | 19960.43 | 22870.77 | 28.75 | 57.5 | Mail/queue/state; coordinate four claims |

Total remaining: **64Gi requested / 128Gi nominal aggregate replicas**, across
**15 claims and seven apps**. BookStack's apparent total and 1.25Gi target remain
provisional because its unmounted old config claim does not represent current
uploads. Resolve that blocker before copying it. Sonarr is the next independent
unit to investigate (1Gi); then youtube-dl Material (1.5Gi), by historical size.

## Latest completed size-ranked batch

The approved batch moved the coordinated Calibre/Calibre Web/Kavita/shared
library unit (1.75Gi), Profilarr (1Gi) and Radarr (1Gi): **five apps, six claims,
3.75Gi requested per host / 7.5Gi aggregate replicas**. BookStack was skipped
because of its unresolved uploads. Original source claims remain rollback copies.
The Calibre group explicitly shares proxmox2-old placement for its RWO library;
future moves must stop and relocate all three apps and maintenance together.
Calibre Web/Kavita retain read-only library mounts. NAS media/import trees remain
external. All copied files matched and eleven SQLite quick checks passed.
See results for backup/restore evidence and endpoint limitations.

## Capacity

Current nominal remaining budgets after this batch are approximately
**58.36Gi on proxmox2-old / 85.85Gi on proxmox3**. These are calculated as
Longhorn `storageMaximum - reserved - storageScheduled`, without overprovisioning.
They differ from physical free (`storageAvailable`); snapshots, physical
allocation and Longhorn free-space thresholds are separate. With two replicas
on these two hosts, each GiB requested consumes one nominal GiB on **each** host.
The previous 55Gi administrative migration cap remains; completed requests total
12Gi. No disk enlargement/default StorageClass change was made.

Latest Longhorn disk snapshot (**2026-10-24 19:50 UTC**, after restore scratch cleanup):

| Node | Total GiB | Physically used GiB | Physically free GiB | Reserved GiB | Scheduled GiB | Nominal remaining GiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| proxmox2-old | 78.19 | 3.29 | 74.90 | 7.82 | 12.01 | 58.36 |
| proxmox3 | 97.87 | 3.24 | 94.63 | 0.00 | 12.02 | 85.85 |

Both disks report Ready/Schedulable. Assigned capacity includes older tests.

See the [current app summary](current-app-storage-summary-2026-10-24.md) for the
latest disk snapshot and [full assessment](fleet-storage-migration-assessment-2026-10-24.md).
