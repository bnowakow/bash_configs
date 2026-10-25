# Remaining migration priority by size — refreshed 2026-10-25

User confirmed Sonarr, youtube-dl Material and AdGuard Home work after their
approved migration and the initial control-plane blocker. See
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

## Mailpile approved batch — blocked before cutover

User confirmed Sonarr, youtube-dl Material and AdGuard Home work. The remaining
size order is unchanged; BookStack remains first by incomplete historical data,
but its current uploads/config must be located and protected before migration.

**Mailpile was approved as the next batch**, the smallest ready-to-
investigate unit. Keep the three large remaining services as separate stages
rather than committing their combined capacity in one batch.

| Item | Historical apparent data | Proposed claim | Mode |
| --- | ---: | ---: | --- |
| Mailpile data/index state | ~6.45GiB | 9Gi | RWO |
| GnuPG keys | small; included in measured total | 256Mi | RWO |
| **Mailpile total** | **~6.45GiB** | **9.25Gi** | **Two claims, two storage replicas each** |

This adds **9.25Gi nominal scheduling on each host / 18.5Gi aggregate replicas**.
Migrated production requests would total **28Gi / 56Gi aggregate replicas**,
across 27 apps/38 claims. Nominal remaining would become about **42.36Gi on
proxmox2-old / 69.85Gi on proxmox3**. No disk enlargement is needed for this
batch. Source apparent size is historical; re-measure both claims and reassess
headroom before execution. Actual physical allocation/snapshots are separate.

Stop Mailpile before copying, preserve the complete mail/index state and keyring
with permissions, verify file checksums, and test an isolated restore before
cutover/retiring any rollback copy. Keep one state-directory owner, Recreate
and RWO; no concurrent mail/index writers. Validate normal web/login/mail-reading
behavior without sending test mail or printing private key/mail contents.

BookStack may precede Mailpile only after its data-location blocker is resolved
and its true live size is measured; the provisional 1.25Gi is excluded from
this proposed batch. Zabbix (18Gi) and Docker Mailserver (28.75Gi) follow by size
and need separate database/mail-specific plans and capacity review.

This is a proposal/documentation update; no further migration was performed.

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

Current nominal remaining budgets, including the unverified Mailpile staging
reservation, are about **42.36Gi on proxmox2-old / 69.85Gi on proxmox3**. This is `storageMaximum - reserved - storageScheduled`,
without overprovisioning. Physical free comes from `storageAvailable` and is
separate from requested capacity, snapshots, filesystem savings and required
free-space margins. With two replicas on two hosts, each requested GiB normally
consumes one nominal GiB on **each** host. The earlier administrative 55Gi
migration cap remains in effect. Current migrated requests total 18.75Gi.

Remaining app requests total 57.25Gi, of which 9.25Gi is already allocated as
unverified Mailpile staging. Another 48Gi would be needed if that staging is
reused; this exceeds the smaller node's current 42.36Gi nominal budget; do not infer permission to enlarge disks or migrate everything. Review
sizes/retention/capacity before the large final apps. No disk enlargement or
default StorageClass change occurred in the completed batch.

Latest Longhorn disk snapshot (**2026-10-25 10:18 UTC**, includes unverified staging):

| Node | Total GiB | Physically used GiB | Physically free GiB | Reserved GiB | Scheduled GiB | Nominal remaining GiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| proxmox2-old | 78.19 | 14.71 | 63.48 | 7.82 | 28.01 | 42.36 |
| proxmox3 | 97.87 | 16.91 | 80.96 | 0.00 | 28.02 | 69.85 |

Both disks report Ready/Schedulable; scheduled capacity includes older tests.

See the [current app summary](current-app-storage-summary-2026-10-24.md) for
current disk figures and [full assessment](fleet-storage-migration-assessment-2026-10-24.md).

## Mailpile execution attempt: blocked, service recovered

The user approved Mailpile. Two target claims (9.25Gi per host) were provisioned,
but the large copy failed during recurring API/k3s outages. Mailpile is restored
on the original local claims, one available replica, HTTPS 200. The targets are
unverified staging; no completion/rank marker changed. See the
[handoff](migrations/mailpile-2026-10-25/HANDOFF.md). Current nominal remaining
is about 42.36Gi/69.85Gi because staging already reserves capacity. Additional
allocations for the remaining apps would be 48Gi per host if Mailpile staging is
reused; avoid double-counting that 9.25Gi. Do not retry bulk I/O until the host
storage/etcd problem and copy failure are understood.
