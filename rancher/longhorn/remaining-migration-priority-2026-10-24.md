# Remaining migration priority by size — 2026-10-24

User confirmed Bindery, Bazarr and Authelia work. The subsequently approved
Audiobookshelf/Scrutiny/Prowlarr batch has now migrated; see its
[results](migrations/media-small-2026-10-24/RESULTS.md).
There are now **18 migrated apps, 24 RWO claims and 8.25Gi requested** production
capacity (16.5Gi nominal aggregate replicas).

## Priority rule

Prioritize **ascending measured apparent source bytes summed across each complete
migration unit**, including its database/metadata claims. Calibre, Calibre Web,
Kavita and their shared library are one unit. This rule prioritizes actual data
size, rather than old oversized PVC requests or just the smallest config claim.
Allocated bytes show source filesystem usage; apparent bytes account for logical
file lengths/sparse files. Neither predicts exact replica/snapshot physical use.

Measurements below are historical from the original 2026-10-24 inventory around
07:51 UTC. Re-measure sources before execution and check current data plus buffer
against proposed quotas. Size priority does not override blockers, coordinated
shutdown or ownership rules. All planned claims are **RWO, two Longhorn replicas,
one application/database owner**; no multi-writer RWX is proposed.

The inventory CSV's `remaining_size_rank` gives the same rank to every claim in
a unit; completed claims have a blank rank. Original size measurements and
existing priority/completion fields are retained.

## Ranked remaining units

| Priority | App / migration unit | Allocated MiB | Apparent MiB | Proposed claims GiB per host | Aggregate replicas GiB | Conditions |
| ---: | --- | ---: | ---: | ---: | ---: | --- |
| 1 | Calibre + Calibre Web + Kavita + shared library | 276.67 | 289.96 | 1.75 | 3.5 | Coordinated four-claim group; stop app/maintenance writers and enforce same-node shared RWO |
| 2 | BookStack | 22.32 | 409.86 | 1.25 | 2.5 | Blocked: locate/protect current container-layer uploads; old config PVC is unmounted |
| 3 | Profilarr | 460.77 | 480.55 | 1 | 2 | SQLite, one owner |
| 4 | Radarr | 556.73 | 605.82 | 1 | 2 | SQLite; media stays NFS |
| 5 | Sonarr | 397.27 | 698.64 | 1 | 2 | SQLite; media stays NFS |
| 6 | youtube-dl Material | 504.44 | 712.13 | 1.5 | 3 | MongoDB + app/user state; coordinate three claims |
| 7 | AdGuard Home | 786.56 | 3020.80 | 4.25 | 8.5 | bbolt single owner; coordinate DNS downtime |
| 8 | Mailpile | 5788.98 | 6600.60 | 9.25 | 18.5 | Mail/index state and GnuPG keyring; two claims |
| 9 | Zabbix | 5708.23 | 13941.71 | 18 | 36 | PostgreSQL; engine-specific shutdown/restore checks |
| 10 | Docker Mailserver | 19960.43 | 22870.77 | 28.75 | 57.5 | Mailboxes/queue/state; coordinate four claims |

Total remaining: **67.75Gi requested / 135.5Gi nominal replicas**, across
**21 claims, 12 apps and one shared library**. BookStack's 1.25Gi remains
provisional: the unmounted old config claim does not account for current uploads.
Its blocker must be resolved before migration regardless of size rank.

The smallest remaining complete unit is the four-claim Calibre group (**1.75Gi
per host / 3.5Gi aggregate replicas**). BookStack follows by historical size but
is blocked; Profilarr is the next independent ready-to-investigate unit (**1Gi
per host / 2Gi aggregate replicas**). Re-measure and plan each unit's specific shutdown before its migration.

## Completed size-ranked batch

The approved three smallest units were Audiobookshelf (1.25Gi), Scrutiny
(1.25Gi) and Prowlarr (0.25Gi), adding **2.75Gi per host / 5.5Gi aggregate**.
All five target claims are now in use; source claims remain rollback copies.
They have been removed from the remaining priority ranks above. Media NFS trees
were not migrated. See results for integrity checks, backups, restored-engine
validation and Scrutiny's virtual-disk SMART warning.

## Capacity

Current nominal remaining budgets after this batch are approximately
**62.11Gi on proxmox2-old / 89.60Gi on proxmox3**. These are calculated as Longhorn
`storageMaximum - reserved - storageScheduled`, without overprovisioning.
They differ from physical free (`storageAvailable`); snapshots, actual replica
allocation and Longhorn free-space thresholds remain separate constraints.
Two replicas across these two hosts consume the requested nominal capacity on
**each** host, not half on each. The previous 55Gi administrative migration cap
remains in effect. This completed batch stays well below it.

The original pre-batch Longhorn reading was 77.05Gi/96.78Gi physically free,
64.86Gi/92.35Gi nominal remaining; it is historical, not a current usage claim.
See the [current app summary](current-app-storage-summary-2026-10-24.md) for the
latest capacity snapshot and [full assessment](fleet-storage-migration-assessment-2026-10-24.md).
