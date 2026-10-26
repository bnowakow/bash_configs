# Remaining migration priority — refreshed 2026-10-26

BookStack is complete; see [results](migrations/bookstack-2026-10-25/RESULTS.md).
Production migrations total **29 apps, 43 RWO claims and 66.75Gi requested**
(**133.5Gi nominal aggregate replicas**). All use two storage replicas with one
application/database owner. Retained local claims are rollback copies; BookStack's
old unused config PVC is not a copy of its formerly ephemeral live config.

## Remaining units and execution order

Historical size ranking uses summed apparent bytes measured on 2026-10-24;
re-measure before any further migration. CSV `remaining_size_rank` is size order.
**User override: Mailpile remains LAST**, regardless of that ranking.

| Size rank | App | Allocated MiB | Apparent MiB | Target GiB per host | Aggregate replicas GiB | Mode / execution condition |
| ---: | --- | ---: | ---: | ---: | ---: | --- |
| 1 | Mailpile | 5788.98 | 6600.60 | 9.25 | 18.5 | RWO; **LAST**; existing staging is unverified |
| 2 | Docker Mailserver | 19960.43 | 22870.77 | 28.75 | 57.5 | RWO; cutover complete 2026-10-26; source PVCs deleted, PV data retained |

Remaining total: **9.25Gi / 18.5Gi aggregate replicas, two claims, one app**.
Mailpile requires mail/index/keyring preservation. No shared-writer RWX
conversion or further migration is authorized by this document.

## Latest completed migration: BookStack

Two claims: config 256Mi and MariaDB 1Gi, both RWO/two replicas, total 1.25Gi.
The live config was in the container layer, not the old unused config PVC.
Its files were preserved with verified hashes, modes, ownership and symlinks,
then mounted persistently. A chart encryption-key regeneration was caught;
the original key is now preserved in a dedicated externally managed Secret and
explicitly referenced by the app. MariaDB was copied stopped at 4MiB/s and
checked in isolation. Fresh NAS backups of both targets were independently
restored, verified by file hashes/metadata, and the restored DB passed table
checks and source-matching checksums. See results for initial failed-check retry
and final runtime validation. Images/chart versions stayed unchanged.

## Mailpile historical attempt

The earlier bulk copy failed during recurring API/k3s outages; the original
local service was restored. Two **unverified staging claims reserve 9.25Gi on
each host**, excluded from production migration totals. See the
[handoff](migrations/mailpile-2026-10-25/HANDOFF.md). These are neither successful
backups nor verified migration targets. Keep Mailpile last and resolve its prior
I/O/control-plane failure before retrying.

## Capacity

Following both authorized expansions to 150GiB on 2026-10-25,
nominal remaining budgets (both measured at 18:36:10 UTC), including Mailpile
staging, are approximately **94.76Gi on proxmox2-old / 99.82Gi on proxmox3**.
At that snapshot proxmox2-old scheduled capacity was temporarily lower due to
missing/failed detached replica placements. The five production exceptions
recovered during application restoration at approximately 20:14 UTC; re-measure
the budget before admitting another migration. Its NVMe reliability warning
and the incident hold still block further migration admission.
Nominal budget is total minus reserved minus scheduled; physical free is separate.
Mailpile staging (9.25Gi per host) is already included in the post-expansion
capacity snapshot. That snapshot predates the Docker Mailserver staging
allocation and cutover, so remeasure current budgets before another migration.
Following successful user-initiated migrations
of VM 700 and 601 to proxmox5 (completed 18:59:03 and 19:04:48 UTC), proxmox2-old
has **84.79GiB physical pool free / 37.59GiB additional allocation headroom above
a 20% pool margin**. The former 3.76GiB physical headroom is historical. This
improves capacity but is **not a completed migration admission review**: re-measure
mail data, allow snapshot/metadata and competing pool growth, verify replicas
and backups, and account for the persistent NVMe reliability warning. Neither
28.75GiB requested capacity nor sparse filesystem free space establishes the
actual physical allocation needed. See the [migration monitoring record](io-pressure-incident-2026-10-25.md).

The administrative **55Gi migration cap remains unchanged**. On 2026-10-26 the
user explicitly authorized Docker Mailserver, including this task-specific
exception. The warm copy and final stopped-writer sync completed, then Fleet
switched the app to four Longhorn claims (28.75GiB requested per host; about
23.45GiB actual). The app is Ready 1/1 and all four volumes are healthy with
two replicas. The four original local-path PVCs were deleted on user
instruction at 17:30 CET. Their PVs had Retain policy; the old local data
directories and released PV objects were removed by 17:34 CET. About 20GiB of
apparent local data was reclaimed on proxmox3. The cutover raised production
requests from 38GiB to 66.75GiB; authorization does not generally raise the cap.
At the 16:52 CET pre-cutover check, proxmox2-old
had 63.24GiB nominal room and 21.29GiB physical pool headroom above its 20%
free-space floor. The user confirmed a CloudCasa backup of the source local-path
claims; backup contents were not independently inspected. Remeasure pool
headroom before another migration. See the [current post-expansion capacity
and handoff](README-4-expand-storage.md#live-post-expansion-capacity-and-mailserver-copy--2026-10-26-1652-cet).

## Host expansion target and completed local resize

See [host expansion procedure and sizing](README-4-expand-storage.md): the user
selected **150GiB per host**. Both grows are complete: proxmox3 100 → 150GiB;
proxmox2-old 80 → 150GiB. Sparse virtual capacity is not guaranteed backing
space. PVC sizes and replica policy are unchanged. The user authorized the
Mailserver migration as a one-task exception to the existing cap; the cap itself
is unchanged.

Post-migration local-path cleanup: 28 unused source claims on proxmox3 were
removed with their data directories and PV records on 2026-10-26. Eleven more
unused migrated source claims remain on proxmox2-old, pending trusted SSH host
key verification. Mailpile's two active local-path claims remain. See the
[reclamation log](local-path-reclamation-2026-10-26.md).
