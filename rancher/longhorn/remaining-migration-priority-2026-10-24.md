# Remaining migration priority — refreshed 2026-10-25

BookStack is complete; see [results](migrations/bookstack-2026-10-25/RESULTS.md).
Production migrations total **28 apps, 39 RWO claims and 38Gi requested**
(**76Gi nominal aggregate replicas**). All use two storage replicas with one
application/database owner. Retained local claims are rollback copies; BookStack's
old unused config PVC is not a copy of its formerly ephemeral live config.

## Remaining units and execution order

Historical size ranking uses summed apparent bytes measured on 2026-10-24;
re-measure before any further migration. CSV `remaining_size_rank` is size order.
**User override: Mailpile remains LAST**, regardless of that ranking.

| Size rank | App | Allocated MiB | Apparent MiB | Target GiB per host | Aggregate replicas GiB | Mode / execution condition |
| ---: | --- | ---: | ---: | ---: | ---: | --- |
| 1 | Mailpile | 5788.98 | 6600.60 | 9.25 | 18.5 | RWO; **LAST**; existing staging is unverified |
| 2 | Docker Mailserver | 19960.43 | 22870.77 | 28.75 | 57.5 | RWO; next independent candidate, but capacity/cap review required |

Remaining total: **38Gi / 76Gi aggregate replicas, six claims, two apps**.
Docker Mailserver requires coordinated protection of mailboxes, queues, config
and state; Mailpile requires mail/index/keyring preservation. No shared-writer
RWX conversion or further migration is authorized by this document.

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
Proxmox2-old scheduled
capacity is temporarily lower due to missing/failed detached replica placements;
its budget must be re-measured after recovery. Its NVMe reliability warning
and the incident hold still block further migration admission.
Nominal budget is total minus reserved minus scheduled; physical free is separate.
If the Mailpile staging can eventually be reused, additional remaining allocation
is **28.75Gi per host**, all for Docker Mailserver. This fits the displayed
nominal budgets after the grows, but **does not pass physical-pool admission**:
proxmox2-old has **50.96GiB physical pool free**, only **3.76GiB above a 20%
pool margin**, and its NVMe reliability warning remains. Filesystem-free
capacity on a sparse zvol does not establish space for copying more data.

The administrative **55Gi migration cap remains**. Production requests are 38Gi;
adding the current Mailserver proposal would reach **66.75Gi**, exceeding it.
Re-measure actual mail data and review conservative sizing/capacity/cap before
another stage. No disk enlargement, replica-count reduction or default
StorageClass change is authorized. See the
[current storage summary](current-app-storage-summary-2026-10-24.md) for fresh
Longhorn-reported disk figures and [assessment](fleet-storage-migration-assessment-2026-10-24.md)
for historical evidence.

## Host expansion target and completed local resize

See [host expansion procedure and sizing](README-4-expand-storage.md): the user
selected **150GiB per host**. Both grows are complete: proxmox3 100 → 150GiB;
proxmox2-old 80 → 150GiB. Sparse virtual capacity is not guaranteed backing
space. PVC sizes, replica policy and the migration cap are unchanged.
