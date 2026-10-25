# Remaining migration priority — refreshed 2026-10-25

Zabbix PostgreSQL is now on Longhorn; see [results](migrations/zabbix-2026-10-25/RESULTS.md).
Production migrations total **27 apps, 37 RWO claims and 36.75Gi requested**
(**73.5Gi nominal aggregate replicas**). All use two storage replicas and a
single application/database owner. Original local claims are retained rollback
copies and excluded from remaining counts.

## Size ranking and execution order

Rank remaining complete migration units by historical summed apparent bytes.
CSV `remaining_size_rank` records size order, not authorization/execution order.
Measurements are from 2026-10-24 and require refreshing before migration.
**User override: Mailpile must be last**, despite its smaller size.

| Size rank | App | Allocated MiB | Apparent MiB | Target GiB per host | Aggregate replicas GiB | Mode / execution condition |
| ---: | --- | ---: | ---: | ---: | ---: | --- |
| 1 | BookStack | 22.32 | 409.86 | 1.25 | 2.5 | RWO; held until actual live uploads/config are located and protected; old config PVC unmounted |
| 2 | Mailpile | 5788.98 | 6600.60 | 9.25 | 18.5 | RWO; **LAST by user decision**; failed staging is unverified |
| 3 | Docker Mailserver | 19960.43 | 22870.77 | 28.75 | 57.5 | RWO; next separate candidate to assess after Zabbix, subject to capacity and mail-specific plan |

Remaining total: **39.25Gi / 78.5Gi aggregate replicas, eight claims, three apps**.
BookStack's 1.25Gi is provisional and excludes an unresolved live data location;
copying its old unused config claim would not protect current uploads. Mailpile
requires coordinated index/mail/keyring preservation. Docker Mailserver requires
coordinated shutdown/protection of mailboxes, queues, configuration and state.
No shared-writer RWX conversion or next migration is authorized by this plan.

## Latest completed migration: Zabbix

One 18Gi RWO claim, two replicas. PostgreSQL-native backup was throttled to
4MiB/s with a spread checkpoint; Zabbix writers and cleanup were stopped.
SHA256 manifest/WAL verification and isolated PostgreSQL recovery matched the
source database identity, schema and table count. A fresh native NAS backup
completed before Fleet cutover; original local data is retained. The native
NAS snapshot was not separately restored. See results for runtime checks.
PostgreSQL's exact source 16.15 image is pinned; Zabbix stays ubuntu-7.4.16.

## Mailpile attempt: historical blocker, source service recovered

The earlier Mailpile bulk copy failed during recurring API/k3s outages. Mailpile
was restored on original local claims. Its two unverified target claims reserve
**9.25Gi on each host**, excluded from migrated production totals. They cannot
be treated as successful backups or populated migration targets. See the
[handoff](migrations/mailpile-2026-10-25/HANDOFF.md). Keep Mailpile last and
investigate the original I/O/control-plane problem before a retry.

## Capacity

Remaining nominal budgets include Mailpile staging: approximately **24.36Gi on
proxmox2-old / 51.85Gi on proxmox3**. This is maximum minus reserved minus
scheduled, separate from physical free (`storageAvailable`) and snapshots.
Remaining proposals total 39.25Gi, but Mailpile staging already reserves 9.25Gi;
additional allocation would be **30Gi per host** if staging is eventually reused.
The smaller host is therefore short by approximately **5.64Gi nominally** for
all remaining proposals. Docker Mailserver alone (28.75Gi) also exceeds that
host's current nominal budget by ~4.39Gi.

The administrative **55Gi migration cap remains**. Current production requests
are 36.75Gi; adding Docker Mailserver would reach 65.5Gi, exceeding that cap.
Do not enlarge disks, change replica counts or exceed the cap implicitly.
Re-measure actual mail data and review conservative targets/capacity first.
No default StorageClass change or disk enlargement occurred.

Use the [current app summary](current-app-storage-summary-2026-10-24.md) for
the latest Longhorn-reported physical/scheduled figures and
[assessment](fleet-storage-migration-assessment-2026-10-24.md) for historical evidence.
