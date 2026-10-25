# Remaining migration priority by size — refreshed 2026-10-25

Sonarr, youtube-dl Material and AdGuard Home have completed their approved
migration after the initial control-plane blocker. See
[execution and backup/restore evidence](migrations/sonarr-ytdl-adguard-2026-10-24/RESULTS.md).
Production migrations total **26 apps, 36 RWO claims and 18.75Gi requested**
(**37.5Gi nominal aggregate replicas**). Original local claims remain rollback
copies and are excluded from the remaining app count.

## Priority rule

Rank complete remaining migration units by **summed measured apparent bytes**,
including database/config/key claims. Size priority does not override unresolved
data locations, coordinated shutdown or database ownership constraints.
Measurements below are historical from 2026-10-24; re-measure before execution.
Allocated size reflects source filesystem blocks/compression/sparsity and does
not predict exact Longhorn replica/snapshot physical allocation.

All remaining proposed targets use **RWO and two storage replicas**, with one
application/database owner. No shared-writer RWX conversion is proposed.
CSV `remaining_size_rank` contains the same rank on each claim of the unit;
completed claims have blank ranks. Original measurement values are retained.

## Ranked remaining units

| Priority | App | Allocated MiB | Apparent MiB | Proposed GiB per host | Aggregate replicas GiB | Conditions |
| ---: | --- | ---: | ---: | ---: | ---: | --- |
| 1 | BookStack | 22.32 | 409.86 | 1.25 | 2.5 | Held: locate/protect current config/uploads; old config PVC is unmounted |
| 2 | Mailpile | 5788.98 | 6600.60 | 9.25 | 18.5 | Mail/index state and GnuPG keys; coordinate both claims |
| 3 | Zabbix | 5708.23 | 13941.71 | 18 | 36 | PostgreSQL; engine-aware shutdown/restore validation |
| 4 | Docker Mailserver | 19960.43 | 22870.77 | 28.75 | 57.5 | Mailboxes/queue/state; coordinate four claims |

Remaining total: **57.25Gi requested / 114.5Gi nominal aggregate replicas**,
across **nine claims and four apps**. BookStack's historical measurement and
1.25Gi target are incomplete/provisional: copying its unmounted config PVC
would not protect current uploads. Resolve that blocker first. Mailpile is the
next independent unit by measured size (9.25Gi), followed by Zabbix (18Gi) and
Docker Mailserver (28.75Gi); these require separate plans and refreshed sizes.

## Latest completed batch

Sonarr (1Gi), youtube-dl Material (1.5Gi across appdata/users/MongoDB) and
AdGuard Home (4.25Gi across config/data) added **6.75Gi per host / 13.5Gi
aggregate replicas**. All six stopped copies matched checksums. Sonarr passed
two SQLite checks; MongoDB passed full validation of 16 collections across four
databases; AdGuard's stats and session bbolt files passed integrity checks.
App/MongoDB startup was coordinated, credentials and NFS media preserved, and
DNS validated on both node IPs. See results for backup/restore scope and the
initial failed-check retry; historical outage details remain in HANDOFF.md.

## Capacity

Current nominal remaining budgets are about **51.61Gi on proxmox2-old /
79.10Gi on proxmox3**. This is `storageMaximum - reserved - storageScheduled`,
without overprovisioning. Physical free comes from `storageAvailable` and is
separate from requested capacity, snapshots, filesystem savings and required
free-space margins. With two replicas on two hosts, each requested GiB normally
consumes one nominal GiB on **each** host. The earlier administrative 55Gi
migration cap remains in effect. Current migrated requests total 18.75Gi.

All remaining 57.25Gi would exceed the smaller node's current nominal remaining
budget; do not infer permission to enlarge disks or migrate everything. Review
sizes/retention/capacity before the large final apps. No disk enlargement or
default StorageClass change occurred in the completed batch.

Latest Longhorn disk snapshot (**2026-10-25 07:07 UTC**, after scratch cleanup):

| Node | Total GiB | Physically used GiB | Physically free GiB | Reserved GiB | Scheduled GiB | Nominal remaining GiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| proxmox2-old | 78.19 | 8.66 | 69.53 | 7.82 | 18.76 | 51.61 |
| proxmox3 | 97.87 | 8.61 | 89.26 | 0.00 | 18.77 | 79.10 |

Both disks report Ready/Schedulable; scheduled capacity includes older tests.

See the [current app summary](current-app-storage-summary-2026-10-24.md) for
current disk figures and [full assessment](fleet-storage-migration-assessment-2026-10-24.md).
