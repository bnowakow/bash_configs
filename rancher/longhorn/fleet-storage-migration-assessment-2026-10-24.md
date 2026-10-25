# Fleet local-storage to Longhorn assessment — 2026-10-24

This is a read-only assessment for a later migration plan. No workloads, PVCs,
replica settings or Fleet manifests were changed. Covers all **41 app bundles
and 8 infrastructure bundles** currently under `fleet/`, including plain-resource
bundles and scaled-down apps. Docker Emby/Nubile are outside the PVC migration
scope; their Fleet ingress bundles are included below.

## Implementation update

The first-wave pilot has since been applied: Homer, Homer-without-auth and
Smokeping now use four 256Mi two-replica Longhorn RWO claims. Original local
claims remain for rollback. See [pilot results](migrations/pilot-2026-10-24/RESULTS.md)
for copy, readiness, backup and isolated restore evidence. The inventory and
remaining-wave estimates below describe the pre-migration measurement.

### Second batch implemented as an explicit singleton-RWO exception

After the RWX audit, the user authorized RWO for ddclient, DuckDNS and
FlareSolverr. All three are now migrated: 256Mi per app, two storage replicas,
one application instance each. They add 0.75Gi per host; total migrated app
requests are now 1.75Gi per host including the first pilot. Source claims are
retained. See [second-batch results](migrations/dns-proxy-2026-10-24/RESULTS.md).
This does not establish shared-writer RWX safety or change the final-group rule
for the other single-owner applications. Measurements below remain historical.

### Third batch implemented: OpenBooks and Ubooquity

User explicitly selected OpenBooks and Ubooquity for singleton RWO migration.
Both are now deployed: OpenBooks books 1Gi and logs 256Mi; Ubooquity config
256Mi. Each volume has two healthy storage replicas, and all source claims are
retained. Added capacity is 1.5Gi per host, bringing migrated application PVC
requests to 3.25Gi per host. Ubooquity's NAS books mount is unchanged. See
[third-batch results](migrations/books-2026-10-24/RESULTS.md) for checksum,
ingress, replica and backup evidence. Ubooquity's completed migration is an
explicit exception to the earlier single-owner-state ordering; it is not an
approval for multi-writer RWX. Source measurements below remain historical.

### Filebot retained storage migrated while the app stays disabled

User explicitly requested migration of Filebot. Its config, unused output and
unused watch claims have been copied to three 256Mi two-replica RWO targets.
Filebot remains at zero replicas; output/watch stay disabled. Added nominal
capacity is 0.75Gi per host, bringing all migrated app requests to 4Gi per host.
Original claims remain for rollback. Initial NAS backups completed using a
temporary read-only helper; detached volumes are skipped by the current recurring
backup policy while Filebot stays disabled. See
[Filebot results](migrations/filebot-2026-10-24/RESULTS.md). This is not an RWX
safety or runtime/license validation, and the usage inventory is historical.

## Small SQLite batch completed — 2026-10-24

With explicit approval, Jellyseerr, Cleanuparr and Uptime Kuma were migrated
to 256Mi RWO claims with two Longhorn replicas each. All remain singleton
writers with Recreate deployments. Offline copy checksums and five SQLite
quick checks passed; HTTPS/API checks and NAS backups completed.
Total migrated production requests are now 4.75Gi (nominal per node), with
71.25Gi still proposed for remaining local apps. Original source PVCs are retained.
See [execution and restore evidence](migrations/sqlite-small-2026-10-24/RESULTS.md).
The original measurements below remain historical; sources are re-measured at cutover.

## Bindery, Bazarr and Authelia completed — 2026-10-24

The next approved batch moved these three apps to 256Mi RWO claims each,
with two Longhorn storage replicas, singleton writers and Recreate deployments.
Offline SHA256 copies and all three SQLite checks passed. Original source
claims remain retained. All six HTTPS endpoint checks passed and Fleet is ready.
Migrated production requests now total 5.5Gi (nominal per node); remaining
conservative proposals total 70.5Gi. See [execution and backup/restore evidence](migrations/sqlite-next-2026-10-24/RESULTS.md).

## Current remaining size priority

The user confirmed the completed SQLite batches work. For the remaining apps,
use the [size-ranked migration proposal](remaining-migration-priority-2026-10-24.md)
and CSV `remaining_size_rank`, ordered by aggregate measured apparent bytes per
complete migration unit. Audiobookshelf, Scrutiny and Prowlarr have now completed
that size-ranked batch (2.75Gi per node, two replicas). The remaining ranking supersedes
the older wave ordering below for remaining work; dependencies/blockers and
single-owner RWO constraints still apply. Re-measure before execution.

## Audiobookshelf, Scrutiny and Prowlarr completed — 2026-10-24

Five PVCs (2.75Gi) were migrated to singleton RWO with two storage replicas.
All stopped-copy checksums and five SQLite checks passed; Scrutiny also passed
InfluxDB TSM/WAL/series-file offline checks. Its hardware collector remains on
proxmox3. The three original summary device records are retained; the restarted
collector additionally found three virtual SCSI disks with unsupported SMART
checks. See [execution and backup/restore evidence](migrations/media-small-2026-10-24/RESULTS.md).
Migrated production requests total 8.25Gi/24 claims across 18 apps; remaining
conservative requests total 67.75Gi/21 claims. Original claims remain retained.

## Next batch proposal after successful user tests

User confirmed the Audiobookshelf/Scrutiny/Prowlarr batch works. The next
size-prioritized executable proposal is the coordinated Calibre/Calibre Web/
Kavita/library unit (1.75Gi), Profilarr (1Gi) and Radarr (1Gi): five apps/six
claims, 3.75Gi per host / 7.5Gi aggregate replicas. BookStack remains rank 2 by
historical measured size but is held pending protection of its real uploads.
See the [priority table and capacity snapshot](remaining-migration-priority-2026-10-24.md).
Re-measure first; preserve same-node placement for all Calibre RWO consumers.
This proposal update changes no app manifests or live workloads.

## Calibre group, Profilarr and Radarr completed — 2026-10-24

The approved five-app/six-claim batch has now moved to Longhorn RWO with two
storage replicas. All file checksums and eleven SQLite checks passed. All
Calibre shared-library consumers, including cover maintenance, explicitly stay
on proxmox2-old; Calibre Web/Kavita retain read-only library mounts. Maintenance
was suspended during the coordinated move and resumed afterward. Original
claims remain retained. Migrated production requests now total 12Gi/30 claims
across 23 apps; remaining proposals total 64Gi/15 claims across seven apps.
See [execution and backup/restore evidence](migrations/calibre-arr-2026-10-24/RESULTS.md).
The preceding proposal sections are historical; use the remaining size ranks
for future work. BookStack remains held pending discovery of current uploads.

## Next proposal after Calibre/arr user validation

User confirmed all five apps in the latest batch work. By the remaining
size ranks, propose Sonarr (1Gi), youtube-dl Material (1.5Gi), then AdGuard Home
(4.25Gi): six RWO claims, 6.75Gi per host / 13.5Gi aggregate replicas. BookStack
remains held despite its smaller historical size until live uploads are found.
Re-measure first; coordinate MongoDB recovery checks and preserve independent
DNS/tool access during the AdGuard shutdown. See the [ranked proposal and fresh
capacity snapshot](remaining-migration-priority-2026-10-24.md). This planning
update changes no live workload.

## Sonarr, youtube-dl Material and AdGuard Home completed — 2026-10-25

The approved six-claim batch is on Longhorn RWO with two replicas. All stopped
copy checksums passed; Sonarr passed two SQLite checks, MongoDB passed full
validation of 16 collections across four databases, and both AdGuard bbolt DBs
passed integrity checks. MongoDB was activated before its app; DNS/HTTPS work.
The initial etcd outage blocked preflight, and a failed isolated MongoDB UID
check blocked cutover until corrected/re-copied; source data was preserved.
Original local claims remain retained. Production migrations total 26 apps,
36 RWO claims and 18.75Gi requested; remaining proposals total 57.25Gi/9 claims.
See [execution and backup/restore evidence](migrations/sonarr-ytdl-adguard-2026-10-24/RESULTS.md).
Preceding proposals are historical; use the current remaining priority ranks.

## Next size-prioritized proposal after user validation — 2026-10-25

User confirmed Sonarr/youtube-dl Material/AdGuard Home work. Recommend Mailpile
alone next (9Gi data + 256Mi keys = 9.25Gi per node, 18.5Gi aggregate replicas),
the smallest remaining independent unit after held BookStack. Re-measure and
protect mail/index/keyring state, stop its writer, and validate isolated restore.
BookStack remains blocked on locating current uploads; Zabbix/Mailserver remain
later separate stages by measured size. See the [priority plan and live capacity](remaining-migration-priority-2026-10-24.md). No migration performed by this update.

## Zabbix completed; Mailpile moved last — 2026-10-25

The preceding batch totals/proposals are historical. Zabbix now uses one 18Gi
Longhorn RWO claim with two replicas. Native PostgreSQL backup, SHA256/WAL
verification and isolated recovery passed before a fresh NAS backup and Fleet
cutover. Source local data is retained; the exact PostgreSQL 16.15 image is
pinned and Zabbix remains ubuntu-7.4.16. The native NAS snapshot was not separately
restore-tested. See [results](migrations/zabbix-2026-10-25/RESULTS.md).

Current production total: **27 apps / 37 claims / 36.75Gi requested**.
Remaining: **3 apps / 8 claims / 39.25Gi**, including provisional BookStack.
Mailpile remains local; its 9.25Gi unverified staging is a separate allocation.
**User requires Mailpile last.** BookStack is held on its live uploads blocker;
Docker Mailserver is the next independent candidate but its 28.75Gi proposal
exceeds current smaller-node nominal capacity and the 55Gi migration cap when
added to production. Re-measure/review capacity before requesting another stage.
See [current priority/capacity](remaining-migration-priority-2026-10-24.md).

## BookStack completed — 2026-10-25

BookStack's container-layer config/uploads were located and preserved, resolving
the old unmounted-config-PVC blocker. Config 256Mi and MariaDB 1Gi now use
Longhorn RWO/two replicas. App encryption-key regeneration by the chart was caught
and the original key explicitly retained in an external Secret; database
credentials stayed unchanged. Stopped copies, isolated DB checks and independent
native NAS restores passed. Original DB data and a verified private live-config
archive were preserved. See [results](migrations/bookstack-2026-10-25/RESULTS.md).

The preceding totals/proposals are historical. Current production total is
**28 apps / 39 claims / 38Gi**. Remaining is **2 apps / 6 claims / 38Gi**:
Docker Mailserver 28.75Gi and Mailpile 9.25Gi; **Mailpile remains last**.
Mailpile's unverified staging already reserves 9.25Gi separately. Docker Mailserver
requires capacity and the existing 55Gi cap review before another stage.
See the [current plan](remaining-migration-priority-2026-10-24.md).

## Revised migration order: shared-state restrictions go last

User decision after the pilot: **defer every app whose persistent state is not
safe for independent concurrent writers on Longhorn RWX to the same final
migration group as SQLite apps**, regardless of database engine. This ordering
supersedes the previous waves 2/3; capacities remain planning estimates.

The final group includes all apps in B, C and D: AdGuard Home (bbolt), SQLite
apps, Ubooquity's embedded database, Mailpile's index/keyring state, BookStack/
MariaDB, Zabbix/PostgreSQL, Scrutiny/InfluxDB, youtube-dl/MongoDB, mailserver state,
and the entire shared Calibre group including Kavita and maintenance Jobs.
Do not promote an app to an earlier batch merely because it does not use SQLite.
Unknown shared-write behavior stays in review, rather than being assumed safe.

RWX access mode permits mounting from multiple nodes; it does not certify
application-level concurrent writes. “Final group” here means unsafe or
unverified **shared-state multi-instance use**, not a blanket claim that every
one of these applications can never use an NFS volume with a single owner.
The default eventual migration for this group remains singleton Longhorn RWO.

The [RWX safety audit](rwx-safety-audit-2026-10-24.md) is now complete for
ddclient, DuckDNS and FlareSolverr: no active-active shared-writer migration
is approved; configuration-only or unnecessary PVCs should be redesigned first.

Remaining persistence/ownership review covers ddclient, DuckDNS, FlareSolverr,
OpenBooks and disabled Filebot. Their low-value PVCs may be unnecessary. None
is approved as an active-active RWX workload; confirm what writes the volume
before choosing persistence or a migration batch. There is currently **no
additional pre-approved batch of proven shared-writer-safe applications**.

Completed pilot stays unchanged: Homer pair and Smokeping already use RWO.
Smokeping's RRD files require one writer, and Homer editors/copy Jobs have
controlled writers; neither pilot result establishes generic multi-writer RWX
safety. No re-migration, scaling or storage change is implied by this regrouping.

## Decision

Most persistent application configuration and databases are reasonable candidates
for **Longhorn RWO, with one active application/database instance**. SQLite is
not a reason to reject Longhorn block storage. It is a reason to reject using
shared RWX storage as a way to run independent application writers on several
nodes. Storage replication and application replication are separate decisions.

Use these groups:

- **A — files/configuration:** suitable pilot migrations; RWX only where file
  sharing is intentional and concurrent edits are controlled.
- **B — embedded database/single-owner state:** migrate to RWO, retain one
  active owner, preserve `Recreate` behavior. No shared RWX database files.
- **C — database/mail services:** technically suitable for RWO, but require
  application-consistent backup/copy and performance checks. Do later.
- **D — shared Calibre storage:** migrate the entire consumer group together;
  explicit same-node placement and coordinated writers are prerequisites.
- **E — optional/defer:** little durability benefit, disabled workload, logs,
  caches or bulk content better left on NAS. Review before spending capacity.
- **F — no application PVC:** nothing to migrate directly.

**Revised decision: start on the existing disks; no disk purchase or resize is
required for the initial migration waves.** Fresh measurements are **33.822 GiB
allocated / 49.018 GiB apparent** across 45 local PVCs. The former 145/158Gi
proposal and 256/320Gi-per-host recommendation were generous growth scenarios,
not minimum requirements, and are superseded as the starting plan.

The lean proposal is **73Gi for core candidates**, **76Gi including optional
claims**. These are fallback sizes if every listed claim is eventually retained,
not authorization to migrate them all. The completed pilot uses **1Gi per node** with two replicas. The former
14.25Gi initial scope is now deferred under the revised final-group ordering. Keep the current Longhorn disk sizes and expand only after
observed growth justifies it. All database/access-mode recommendations below
remain applicable.

## Evidence and limitations

Sources inspected: every Fleet bundle and values file; current PVC/PV mappings,
Deployment/StatefulSet replica counts, container mounts/images, StorageClasses,
Longhorn nodes/settings; bounded read-only database filename/header checks;
and existing documentation in this directory. SQLite headers were checked
without reading table contents. No full database consistency checks were run.

Fresh sizing evidence is in
[local-pvc-usage-2026-10-24.csv](local-pvc-usage-2026-10-24.csv). Each local PV
was measured on its affinity node through root SSH using `du -sx -B1` and
`du -sx -B1 --apparent-size`. `-x` avoids crossing filesystems. All 45
measurements completed without warnings. They are live, sequential observations,
not a frozen application-consistent snapshot. Sizes can change during collection.
No NAS media trees or container writable layers were measured or included. In particular, BookStack's config claim is currently unmounted; its live container-layer data needs a separate audit before these PVC totals can be treated as its complete state. No capacity/performance benchmark
or growth-rate study was performed. Database classifications marked inferred
must be confirmed against the installed version before cutover.

There are also two existing 10Mi Longhorn RWX test/restore PVCs; these are not
local-PVC migration candidates and are excluded from the 45-claim totals.

## RWO, RWX and multiple writers

Longhorn RWO presents a block-backed filesystem to an attached node. The
recommendations here assume a Filesystem-mode PVC with ext4, one active stateful
owner and correct detachment before failover. This differs from RWX, which
Longhorn serves through NFS share-manager pods. [Longhorn RWX documentation](https://longhorn.io/docs/1.13.0/nodes-and-volumes/volumes/rwx-volumes/).

SQLite WAL requires database clients on the same host; network-filesystem
locking and shared-memory semantics are a problem. A single SQLite application
on an RWO filesystem is a candidate; placing its database on RWX/NFS for
cross-node readers/writers is not the default plan. SQLite can serialize
transactions within a supported local-filesystem deployment; “single owner”
here is an application deployment policy, not a claim that SQLite cannot have
multiple connections. [SQLite WAL](https://www.sqlite.org/wal.html),
[SQLite network filesystem considerations](https://www.sqlite.org/useovernet.html).

RWO is **one node**, not necessarily one pod. Several pods can mount an RWO
volume on that node. RWO alone does not enforce singleton application ownership
or schedule all consumers together. Preserve one replica and non-overlapping
rollouts; add explicit co-location for legitimate shared consumers. Do not
force-detach from a node that may still be writing without fencing it first.
[Kubernetes access modes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes).

All observed stateful application Deployments currently use `Recreate` and one
replica, except `homer-test` (two replicas). Zabbix web/webservice use rolling
updates but do not mount the PostgreSQL data directory. PostgreSQL itself is a
single-replica StatefulSet. These facts should be rechecked at migration time.

## App-by-app assessment

Claims below are the **live claims**, not guesses from chart defaults. Every
listed source claim is local-path unless explicitly marked Longhorn. Suggested
capacities for each claim and total per namespace appear in the sizing tables.

### A — configuration/files: useful early candidates

| Fleet app | Current storage and state | Recommendation and conditions |
| --- | --- | --- |
| `homer` | `homer-config`; dashboard assets plus code-server editor state | Good first candidate, RWO with existing single replica. RWX is plausible for static assets, but editor state/extensions should have one writer or a separate RWO volume. Coordinate with the hourly copy bundle below. |
| `homer-without-auth` | `homer-without-auth-config`; copied assets plus editor | Good candidate coordinated with `homer`. Its copy Job mounts both claims, so two RWO volumes require all relevant pods/jobs to co-locate. Separate immutable assets from editor state before pursuing active-active RWX. |
| `smokeping` | `smokeping-config`, `smokeping-data`; config and RRD history | Good RWO candidate, preserving one RRD writer. RRD updates create ongoing small writes; check latency and retained-history growth. RWX does not make multiple pollers safe against the same files. |

### B — embedded database or single-owner application state

**Recommended default: Longhorn RWO, one active instance; not shared RWX.**
These remain migration candidates, in a separate category from file-only apps.

| Fleet app | Live claims / database evidence | Recommendation and remaining checks |
| --- | --- | --- |
| `adguard-home` | `adguard-home-config`, `adguard-home-data`; work directory has `stats.db` and `sessions.db`. Installed v0.107.79 statistics code uses **bbolt**, not SQLite. | Strong durability candidate, but DNS outage is critical: pilot another app first, provide independent fallback DNS, then migrate both claims together. Keep one owner per data directory. Multiple DNS instances need independent working directories plus deliberate config synchronization. |
| `audiobookshelf` | `audiobookshelf-config`, `audiobookshelf-metadata`; `/config/absdatabase.sqlite` header confirmed SQLite | Good RWO candidate. Move config and metadata as one application unit; leave both audiobook NFS mounts on NAS. Metadata includes covers/backups and can grow much faster than initial usage. |
| `authelia` | `authelia-config`; explicit `/config/db.sqlite3` configuration, in-memory sessions, Redis disabled | Good RWO durability candidate; retain one replica. For application HA, first change to an external SQL backend and shared Redis sessions; RWX is not that migration. Preserve encryption keys and user file. |
| `bazarr` | `bazarr-config`; `/config/db/bazarr.db` SQLite confirmed | Good RWO candidate; keep NAS media mount. Stop its process for final copy and preserve permissions. |
| `bindery` | `bindery-config`; upstream describes SQLite/WAL; shell exec unavailable in installed container | Good RWO candidate after version-specific backup/path confirmation. No destructive inspection attempted. Preserve shared NAS download/library mount for hardlinks. Do not infer multi-instance safety from the SQL engine alone. |
| `cleanuparr` | `cleanuparr-config`; `cleanuparr.db`, `users.db`, `events.db` SQLite confirmed | Good RWO candidate; copy all DBs and config together with app stopped. Current upstream also offers PostgreSQL, but backend migration is separate from this storage change. |
| `jellyseerr` | `jellyseerr-config`; `/app/config/db/db.sqlite3` plus WAL/SHM observed | Good RWO candidate. Preserve database, settings and credentials; stop writer for final copy. Do not mount config RWX for parallel instances. |
| `kavita` | `kavita-config`; `/config/kavita.db` SQLite confirmed; also reads `calibre-library` | Migrate its private config as RWO; migration scheduling must respect shared-library group D. Leave `/books` on NAS. Keep `/library` read-only. |
| `profilarr` | `profilarr-config`; `/config/data/profilarr.db` SQLite confirmed | Good RWO candidate. Use new, right-sized claim rather than carrying over the existing 100Gi declaration. Ensure quoted PVC kinds are handled by upgrade tooling, and preserve Helm/Fleet ownership metadata. |
| `prowlarr` | `prowlarr-config`; `prowlarr.db` and `logs.db` SQLite confirmed | Good RWO candidate. Keep one active instance and preserve both DBs plus app settings/API credentials. |
| `radarr` | `radarr-config`; `radarr.db` and `logs.db` SQLite confirmed | Good RWO candidate; leave large NAS media/download trees in place. Verify database-backed paths and permissions after cutover. |
| `sonarr` | `sonarr-config`; `sonarr.db` and `logs.db` SQLite confirmed | Good RWO candidate, same constraints as Radarr. Its measured state is larger than the other Arr configs; use its own target size rather than a generic tiny config claim. |
| `ubooquity` | `ubooquity-config`; embedded DB file `/config/ubooquity-6.mv.db` observed (H2-style filename, not a SQLite identification) | Good RWO candidate with one app process. Stop for copy; verify users, library and admin login after restart. Keep NAS books external. Confirm installed DB/backup behavior before migration. |
| `uptime-kuma` | `uptime-kuma-config`; installed 1.23.17 `/app/data/kuma.db` SQLite confirmed | Good RWO candidate with one monitor scheduler. No RWX/NFS data directory; avoid duplicate notifications while old and new instances coexist. |
| `mailpile` | `mailpile-path1`, `mailpile-path2`; mail/index/config data and GnuPG keyring; no SQLite claim made | Useful but later RWO migration: one indexer/keyring owner, stop app for final copy, protect private keys and verify decryption/search. Growing data: do not classify as a tiny config-only app. |

AdGuard's installed statistics backend is verified in
[v0.107.79 source](https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/v0.107.79/internal/stats/stats.go).
bbolt takes a process-level file lock; separate app processes must not share
its working database. [bbolt documentation](https://github.com/etcd-io/bbolt).
AdGuard query logs are also file-backed state; the SQLite example in the request
should not be treated as an observed AdGuard implementation detail.

Authelia explicitly excludes SQLite and memory sessions from multi-instance HA.
[Authelia SQLite](https://www.authelia.com/configuration/storage/sqlite/),
[Authelia statelessness](https://www.authelia.com/overview/authorization/statelessness/).
Audiobookshelf identifies config as SQLite and metadata separately;
[installation storage guidance](https://audiobookshelf.org/docs/documentation/install/docker/).
[Bindery's architecture](https://github.com/vavallee/bindery) identifies SQLite/WAL.
[Uptime Kuma installation guidance](https://github.com/louislam/uptime-kuma/wiki/%F0%9F%94%A7-How-to-Install)
requires appropriate file locking. These upstream network-filesystem warnings
are why RWO block-backed ext4 and NFS-backed RWX are evaluated separately here.

### C — database/mail services: migrate after a benchmark and restore rehearsal

| Fleet app | Current storage and backend | Recommendation and conditions |
| --- | --- | --- |
| `bookstack` | `bookstack-config`, `bookstack-mariadb-data`; separate single-replica MariaDB Deployment | Suitable for RWO. Migrate DB plus app/upload state consistently; use a database-aware backup or a clean DB shutdown. Two MariaDB processes must never share one data directory. **Live BookStack Deployment does not mount `bookstack-config` at all** (`enabled: false` wins). Its measured claim contents may be old. Audit/save current container-layer uploads/config before migration; merely copying this PVC does not prove current app state was preserved. |
| `zabbix` | `postgresql-data-zabbix-postgresql-0`; single PostgreSQL 16 StatefulSet, app/web separate | Suitable but performance-sensitive. Prioritize correct target size and retention planning, then measure storage latency/IOPS. Use PostgreSQL backup/restore or clean shutdown copy. Web replica scaling does not permit sharing PGDATA among database servers. |
| `scrutiny` | `scrutiny-config`, `scrutiny-influxdb`; omnibus image, observed `scrutiny.db` and InfluxDB engine/bolt/sqlite files | Suitable RWO for config/history, one omnibus process. Needs coordinated backup of all embedded/Influx state and latency testing. Host `/run/udev` and privileged SMART collection remain node-specific: moving storage alone does not make monitoring hardware portable. Consider splitting collectors from central web/DB later. |
| `youtubedl-material` | `youtubedl-material-appdata`, `youtubedl-material-users`, `youtubedl-material-mongodb-data`; separate MongoDB Deployment | Suitable RWO for app state and one MongoDB owner per data directory. Identify which state lives in MongoDB versus local app/user files and stop downloads during consistent cutover. Leave audio/subscriptions/video on their existing NAS NFS mounts. Mongo replica sets, if later desired, require separate per-member data volumes. |
| `docker-mailserver` | `docker-mailserver-mail-config`, `docker-mailserver-mail-data`, `docker-mailserver-mail-state`, `docker-mailserver-mail-log`; one mail Deployment | Valuable but late/high-impact migration. Move mail/config/state as a coherent unit, pause mail writers for final sync, preserve UID/GID, test SMTP/IMAP/TLS and queues. RWO only for current topology; a second mail server is not created by sharing the maildir. Logs are optional and should have rotation/retention rather than large replicated capacity. |

Database application replication must use the engine's supported topology,
with separate data directories. PostgreSQL documents consistent filesystem
backup requirements; a live recursive copy is not a valid generic replacement.
[PostgreSQL backup guidance](https://www.postgresql.org/docs/16/backup-file.html).
Scrutiny's upstream describes its collector/web/InfluxDB split:
[Scrutiny](https://github.com/AnalogJ/scrutiny).

### D — shared Calibre claims: defer until scheduling and writer coordination are designed

| Fleet app/bundle | Role | Recommendation |
| --- | --- | --- |
| `calibre` | Own `calibre-config`; writes shared `calibre-library` (`metadata.db` SQLite header confirmed) | Private config is straightforward RWO. Shared library needs same-node consumers and only one active Calibre/maintenance writer. Keep `/books` NAS import tree unchanged. |
| `calibre-web` | Own `calibre-web-config` with SQLite `app.db`/`gdrive.db`; reads `calibre-library` read-only | Private config RWO, one app instance. Keep library read-only. A library RO mount does not make this app stateless: it still writes its private config DB/cache. |
| `calibre-storage` | Owns `calibre-library` and `calibre-web-config` PVC manifests | Change claim references and manifests in a coordinated migration; this is storage ownership, not another independent app's data. Count shared library only once. |
| `calibre-cover-maintenance` | CronJob writes library after scaling Calibre down; then refreshes thumbnails using web config | No new PVC, but a critical migration consumer. Suspend while copying, update both claim names, explicitly co-locate its pod with readers/writers. Preserve the existing GUI-stop/restore behavior; check thumbnail/cache access does not race the web app. |

Kavita (group B) is another read-only library consumer. All these consumers
currently share `apps-calibre` and benefit from local PV node affinity. After
migration, Longhorn RWO attachment alone will not preserve that scheduling.
Use explicit pod affinity/placement for **every consumer**, including Jobs;
ensure both shared RWO claims can attach on the same node. Reconcile chart-made
`truecharts.org/pvc` affinity labels rather than assuming they remain sufficient.

Do not choose RWX/NFS for `metadata.db` merely to remove node affinity. Calibre
explicitly advises against a library on a network drive.
[Calibre FAQ](https://manual.calibre-ebook.com/faq.html#i-am-getting-errors-with-my-calibre-library-on-a-networked-drive-nas).
A later alternative is single-writer RWO plus a separately published read-only
book tree/API. That is an architecture change, not a simple PVC substitution.

### E — optional, defer, or reconsider the persistent volume

| Fleet app | Current storage | Decision |
| --- | --- | --- |
| `ddclient` | `ddclient-config`, declares 100Gi but essentially empty measured state | Low benefit. Review config/credentials and cache requirements; tiny RWO if persistence is useful, otherwise manage config through Secret/ConfigMap. Keep updater singleton. |
| `duckdns` | `duckdns-config`, 100Gi declaration, essentially empty | Low benefit. Stateless DNS updater apart from config/log/cache; do not spend 100Gi of Longhorn scheduling capacity. Review whether a PVC is needed. |
| `flaresolverr` | `flaresolverr-config`, 100Gi declaration, essentially empty | Defer pending content/use audit. Browser sessions are not made application-HA by a shared volume. Do not copy an empty legacy PVC just because it exists. |
| `filebot` | `filebot-config`, `filebot-output`, `filebot-watch`; deployment replicas=0; output/watch disabled in values but old claims remain | No migration while deliberately stopped. Preserve any license/settings in config. Audit old output/watch claims; do not delete them as part of this assessment. Keep bulk working media on NAS if re-enabled. |
| `openbooks` | `openbooks-books`, `openbooks-logs`; downloads nearly empty | Books can use small RWO if local independent downloads are intentional; for a shared/growing media collection prefer NAS. Logs should be rotated/ephemeral or centralised. No active-active downloader sharing by default. |

### F — other app bundles: no independent PVC migration

| Fleet bundle | Storage consequence |
| --- | --- |
| `homer-test` | Already Longhorn: `homer-test-config-longhorn-rwx`, 10Mi, two replicas at the application level. Retain as file-sharing/backup test; two code-server editors still need controlled writes. Not evidence that database RWX is safe. |
| `homer-test-pvc-copy` | Owns the existing 10Mi `homer-test-config-longhorn-rwx` Longhorn RWX PVC and backup-group labels. Already migrated; keep as the storage/bootstrap dependency for `homer-test`, with no additional local capacity to count. |
| `homer-without-auth-config-copy` | Owns destination PVC counted with `homer-without-auth`, plus copy Job/CronJob. Must update claim references and scheduling with group A; no extra volume to count. |
| `homer-config-auth` | Traefik routes/middleware, no PVC. |
| `cleanuparr-localdomain-ingress` | Ingress, no PVC. |
| `profilarr-localdomain-ingress` | Ingress, no PVC. |
| `emby-ingress` | External Compose backend on proxmox3; no Kubernetes app PVC. Compose config/media migration would be a separate task. |
| `nubile-ingress` | External Compose backend on proxmox3; no Kubernetes app PVC. NFS Movies stays external. |
| `ubooquity-admin-redirect` | Traefik middleware/routes, no PVC. |

## Infrastructure bundles (all 8 evaluated)

| Bundle | Decision |
| --- | --- |
| `longhorn` | The destination storage system, not an app data migration. Verify whether Fleet or K3s HelmChart is authoritative before changing defaults; avoid dual ownership. |
| `longhorn-backups` | Recurring backup policy; enroll migrated volumes explicitly, not a PVC migration. |
| `cert-manager` | Certificate controller state lives in Kubernetes objects/Secrets, no local PVC observed. Back up cluster state/Secrets separately. |
| `cert-manager-resources` | Issuers and related objects, no PVC. |
| `traefik-config` (directory `traefik`) | HelmChartConfig; no app PVC migration observed. |
| `traefik-resources` | Routes/middleware/services, no PVC. |
| `scrutiny-cors` | Middleware, no PVC. |
| `cloudcasa` | Backup agent; values supplied by Secret. No non-app PVCs observed in this inventory. Verify backup destination coverage rather than inventing a local-volume migration for it. |

## Capacity policy and current Longhorn-node comparison

“Target/quota” below means **new PVC requested capacity**, not Kubernetes
ResourceQuota and not immediately allocated physical storage. Longhorn thin
provisioning does not remove scheduling limits. Existing local hostPath-style
PVC requests often do not cap directory usage: mail data is 22.238Gi apparent
against 10Gi requested; PostgreSQL is 13.615Gi apparent against 5Gi requested.
Copying either into a target sized from the old request can fail.

Lean sizing policy (revised after capacity review):

1. Baseline remains `max(allocated, apparent)` from the measured CSV. Target
   starts at **125% of baseline**, rounded up to **128Mi (0.125Gi) steps**.
   Default floor is **256Mi**, rather than 1Gi. Specific stateful/growing volumes
   use larger floors: mail 28Gi, PostgreSQL 18Gi, Mailpile data 9Gi, AdGuard work
   4Gi, library/metadata and selected databases 1Gi. These are starting estimates,
   not promises that future growth will stay within 25%.
2. Every target remains above its measured baseline. Re-measure just before
   copy. Do not size a new target using the old local-path capacity declaration.
3. The CSV preserves the previous proposal in `previous_generous_GiB`; active
   `suggested_GiB`, headroom and tables now use lean sizes. `migration_wave`
   identifies the proposed starting order. No actual PVC requests were changed.
4. New smaller claims require new PVC names and a stopped/consistent copy;
   existing PVCs cannot be shrunk. Confirm expandable targets and test online
   expansion of a pilot claim before relying on later growth. Expand a selected
   PVC as needed instead of preallocating years of growth to every app.
5. Shared claims count once. Optional/deferred claims are not in the starting
   wave capacity. The core total is a technical suitability total; some core
   claims are deliberately deferred operationally.

Measured Longhorn disks and remaining budgets (GiB):

| Node | Disk total | Free now | Reserved | Already scheduled | Remaining nominal budget at 100% overprovisioning | Free above 25% minimum |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| proxmox2-old | 78.190 | 78.027 | 7.819 | 0.010 | 70.361 | 58.480 |
| proxmox3 | 97.872 | 97.754 | 0 | 0.020 | 97.852 | 73.286 |

Live settings: overprovisioning 100%, minimum available 25%, node replica soft
anti-affinity disabled. Live `longhorn` StorageClass specifies **one** replica;
manager defaults specify **two**. A migration intended to survive a node loss
must deliberately select a two-replica class/policy and verify actual replicas.
These sources disagree: older README-2 describes a two-replica class, while
current Fleet values and the live class still specify one. Do not apply old
doc commands as if the effective policy has already changed.

[Longhorn scheduling rules](https://longhorn.io/docs/1.13.0/nodes-and-volumes/nodes/scheduling/)
check both nominal scheduling and available space. The 25% threshold is a
scheduling guard, not a permanent per-volume write quota.

| Two-replica scenario | New nominal capacity on EACH node | Fits existing node budgets? |
| --- | ---: | --- |
| Wave 1: Homer pair and Smokeping | 1Gi | Yes: low-risk pilot; includes cross-claim copy Job scheduling work. |
| Former waves 1–2 (now deferred) | 14.25Gi cumulative | Fits nominally, but is not the next batch under the revised ordering. |
| Add Mailpile after verifying growth | 23.5Gi cumulative | Yes, gated on health/backups and actual usage. |
| Add Zabbix after DB benchmark/restore | 41.5Gi cumulative | Yes nominally; physical/snapshot gates below still apply. |
| Every lean core candidate | 73Gi | No on the smaller node: exceeds its 70.361Gi remaining budget by 2.639Gi, without operational reserve. Do not attempt this as a single wave. |
| Every lean fallback claim | 76Gi | No on the smaller node; includes optional work we do not currently recommend. |

### Current implementation order

| Stage | Scope | Additional capacity per node |
| --- | --- | ---: |
| Completed pilot | Homer pair and Smokeping on singleton/co-located RWO | 1Gi already deployed |
| Completed singleton batch 2 | ddclient, DuckDNS, FlareSolverr; explicit RWO authorization | 0.75Gi deployed |
| Completed singleton batch 3 | OpenBooks and Ubooquity; explicit RWO authorization | 1.5Gi deployed |
| Completed retained-storage migration | Filebot config/output/watch copied; app still disabled | 0.75Gi deployed |
| Final group | All B/C/D apps, including AdGuard bbolt, SQLite, other embedded stores and server databases; retain their respective RWO/co-location requirements | Select one batch later; existing per-PVC sizing remains applicable |

The former 13.25Gi wave 2, Mailpile wave 3a and Zabbix wave 3b are no longer
approved sequencing recommendations. Their sizes remain useful for future
budgeting, but all belong to the final group. Shared Calibre topology and
BookStack's unmounted-config finding must still be resolved before their turn.

### Budget gates before every app

- Use two replicas on distinct hosts, explicitly verified; the current default
  class still selects one. No reductions in redundancy just to fit the plan.
- Initial **administrative cap: 55Gi of newly scheduled nominal replicas per
  node** from this migration (not a setting changed in Longhorn). This leaves
  at least 15.361Gi nominal room on the smaller node for planned expansion and
  unexpected volumes. Subtract all other new Longhorn reservations too.
- Physical usage is a separate gate: plan for the incoming copied data plus
  **25% of its baseline as an initial snapshot/churn allowance**, filesystem
  overhead, and **at least 5Gi additional free margin ABOVE Longhorn's 25% disk
  free threshold** on both nodes. Compare this with live actual replica/disk
  usage, not just PVC requests. This is an admission estimate, not a hard
  upper bound on snapshots or write amplification.
- Pause expansion of the migration if these gates fail, a volume is degraded,
  rebuilding is stalled, latency rises, backup fails, or growth is faster than
  assumed. Alert at 70% filesystem usage and schedule expansion by 80%, with
  earlier alerts for fast-growing DB/WAL/mail volumes. Test monitoring before
  migrating valuable state; 256Mi config claims need this discipline.
- Keep NAS backup policy, but review local snapshot retention/churn weekly.
  Fourteen remote backups do not require fourteen complete local snapshots.
  Do not silently remove recovery points simply to squeeze in another app.

### When to consider resizing (not a prerequisite)

Do **not** resize to 256/320Gi per host for this starting plan. Existing disks
have ample capacity for the completed 1Gi pilot; later scope is pending review. Mail and PostgreSQL
account for much of the full-data footprint; moving them is a later value/risk
choice, not a requirement to finish the first phase.

If future measurements justify all 73Gi core targets, a **128Gi final Longhorn
filesystem on proxmox2-old alone** is a plausible next option. Assuming its
current 10% reserve remains proportional, nominal budget would be about
115.2Gi before existing reservations; the current ~97.87Gi proxmox3 disk
already has ~97.85Gi remaining nominal room. The full ~49Gi baseline plus a
25% illustrative snapshot allowance is ~61.3Gi per node, below the ~73.4Gi
physical-use level corresponding to 25% free on the current larger node.
These calculations are feasibility estimates, not approval to migrate mail or
change disks. Recheck live usage, actual snapshot churn, host ZFS-pool space and
rebuild headroom first. A 128Gi sparse zvol is not 128Gi of guaranteed physical
pool space. If those checks fail, keep some large services on local storage.

Two storage nodes still cannot rebuild a second replica onto a third failure
domain while one is down. Maintain the NAS restore path and test failover;
replication is not a backup. NAS media stays external to this budget.

## Existing migration/backup material to reuse

- [October 9 storage estimate](storage-estimate-2026-10-09.md) and
  [old measured CSV](local-pvc-usage-2026-10-09.csv): historical only. Current
  local baseline is ~33.82/49.02Gi versus ~30.89/47.59Gi then; the app/PVC set
  also changed, so this is not a like-for-like growth-rate calculation.
- [AdGuard migration runbook](migrations/adguard-home/README.md), its script,
  overlay, copy Job and PVC definitions: useful phase structure, but not yet
  executed by this assessment. Its 100Mi config/10Gi data targets differ from
  the revised 256Mi config/4Gi data proposal; re-measure retention and reconcile
  deliberately rather than running that older manifest unchanged.
- `migrations/migrate.sh` and existing Homer RWO/RWX transfer manifests: adapt
  to individual writers and claim topology; do not generalize the RWX test to DBs.
- [Backup and restore runbook](README-3-backup-and-restore.md),
  `verify-homer-restore.sh`, and existing restore test: reuse the demonstrated
  NAS backup/restore flow and add database-aware consistency validation.
- [Two-node configuration notes](README-2-update-longhorn-to-use-two-nodes.md):
  revalidate effective StorageClass/Helm ownership as described above.

The Fleet backup job runs at 01:00, retains 14 backups, concurrency one, and
selects the `nas-backup` group. Enroll target volumes explicitly and preserve
source labels. Volume snapshots capture block state, not automatically a
consistent application transaction across multiple PVCs. Plan DB dumps or
quiesced backups and test recovery, including private keys/credentials.
Detached-volume backup behavior and retention must be checked against live
settings before accepting the migration; do not equate an installed job with
complete backup coverage. Backup-store capacity is separate from disk quotas.
A starting retained-block model is `B + 13 × changed_unique_blocks`; no fresh
churn measurement was made, so this report does not assert a NAS quota.

## Additional observed storage mismatch

`bookstack-config` is Bound but is not referenced by the live BookStack
Deployment; its only volumes are ephemeral helpers. The current values explicitly
disable config persistence despite naming an existing claim. Preserve this
finding as a prerequisite: identify where current uploads/config are written,
measure and back them up before any rollout, then decide whether to restore the
intended persistent mount. Do not count the old claim measurement as proof of
complete live BookStack data coverage. No correction/restart was made here.
Filebot output/watch claims are also unreferenced by current Deployments,
consistent with their disabled persistence values; config remains referenced by
the scaled-to-zero Deployment. Unreferenced does not authorize deletion.

## Inputs required for the later migration plan

1. Choose first-wave apps and two-replica StorageClass; resolve Longhorn owner
   (Fleet versus K3s HelmChart) and disk capacity before changing defaults.
2. Re-measure selected claims and growth/retention; verify database-specific
   backups, fsync latency and current target free space. Read-only `du` is not
   an application backup or integrity test.
3. Prepare new claims with explicit sizes, filesystem/access mode, replica
   policy, backup group and Retain protection. Preserve original ownership and
   old rollback data; never change storageClass on a bound claim in place.
4. Suspend affected CronJobs and quiesce ALL writers, including DB sidecars and
   copy jobs. Final copy must preserve ownership, permissions, timestamps and
   sparse files; validate content. For Calibre/Homer multi-claim consumers,
   design co-location before the cutover.
5. Render pinned charts to confirm effective existingClaim mounts, service
   replicas/strategies and node affinity. Validate Helm/Fleet PVC labels and
   ownership without recreating data-bearing PVCs.
6. Apply one cutover at a time, verify Fleet readiness, app-specific read/write
   behavior, external NAS mounts and ingress, then test backup/restore and a
   controlled node-drain/failover before removing rollback options. A claim
   copied successfully is not proof of a safe migration.

## Current measured usage and proposed capacities

All measurements below are GiB (2^30 bytes). Values rounded to 4 decimals;
`0.0000` can mean small nonzero data. Exact bytes, source paths/nodes and
measurement timestamps are retained in the companion CSV. “Optional” flags
exclude those claims from the 73Gi core scenario; they remain in the 76Gi
all-claims fallback scenario. Neither total is the initial migration scope.

### By app namespace (shared claims counted once)

| App namespace | Local claims | Allocated GiB | Apparent GiB | Lean proposed GiB | Core GiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| `apps-adguard-home` | 2 | 0.7681 | 2.9500 | 4.25 | 4.25 |
| `apps-audiobookshelf` | 2 | 0.0022 | 0.0178 | 1.25 | 1.25 |
| `apps-authelia` | 1 | 0.0001 | 0.0003 | 0.25 | 0.25 |
| `apps-bazarr` | 1 | 0.0448 | 0.0652 | 0.25 | 0.25 |
| `apps-bindery` | 1 | 0.0101 | 0.0245 | 0.25 | 0.25 |
| `apps-bookstack` | 2 | 0.0218 | 0.4003 | 1.25 | 1.25 |
| `apps-calibre` | 4 | 0.2702 | 0.2832 | 1.75 | 1.75 |
| `apps-cleanuparr` | 1 | 0.0033 | 0.0097 | 0.25 | 0.25 |
| `apps-ddclient` | 1 | 0.0000 | 0.0000 | 0.25 | 0 |
| `apps-docker-mailserver` | 4 | 19.4926 | 22.3347 | 28.75 | 28.5 |
| `apps-duckdns` | 1 | 0.0000 | 0.0000 | 0.25 | 0 |
| `apps-filebot` | 3 | 0.0065 | 0.0072 | 0.75 | 0 |
| `apps-flaresolverr` | 1 | 0.0000 | 0.0000 | 0.25 | 0 |
| `apps-homer` | 2 | 0.0019 | 0.0017 | 0.5 | 0.5 |
| `apps-jellyseerr` | 1 | 0.0026 | 0.0092 | 0.25 | 0.25 |
| `apps-mailpile` | 2 | 5.6533 | 6.4459 | 9.25 | 9.25 |
| `apps-openbooks` | 2 | 0.0001 | 0.0001 | 1.25 | 0 |
| `apps-profilarr` | 1 | 0.4500 | 0.4693 | 1 | 1 |
| `apps-prowlarr` | 1 | 0.0460 | 0.1577 | 0.25 | 0.25 |
| `apps-radarr` | 1 | 0.5437 | 0.5916 | 1 | 1 |
| `apps-scrutiny` | 2 | 0.0022 | 0.1571 | 1.25 | 1.25 |
| `apps-smokeping` | 2 | 0.0369 | 0.0811 | 0.5 | 0.5 |
| `apps-sonarr` | 1 | 0.3880 | 0.6823 | 1 | 1 |
| `apps-ubooquity` | 1 | 0.0047 | 0.0046 | 0.25 | 0.25 |
| `apps-uptime-kuma` | 1 | 0.0060 | 0.0145 | 0.25 | 0.25 |
| `apps-youtubedl-material` | 3 | 0.4926 | 0.6954 | 1.5 | 1.5 |
| `apps-zabbix` | 1 | 5.5744 | 13.6149 | 18 | 18 |
| **Total** | **45** | **33.8219** | **49.0185** | **76** | **73** |

`apps-calibre` combines Calibre, Calibre Web, Kavita and shared claims.
`apps-homer` combines the production Homer instances. Count shared claims once.

### Per local PVC

| Namespace / PVC | Current request | Allocated GiB | Apparent GiB | Lean GiB | Headroom GiB | Wave |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `apps-adguard-home/adguard-home-config` | 100Gi | 0.0000 | 0.0000 | 0.25 | 0.2500 | completed-sonarr-ytdl-adguard-rwo |
| `apps-adguard-home/adguard-home-data` | 100Gi | 0.7681 | 2.9500 | 4 | 1.0500 | completed-sonarr-ytdl-adguard-rwo |
| `apps-audiobookshelf/audiobookshelf-config` | 4Gi | 0.0004 | 0.0016 | 0.25 | 0.2484 | completed-media-small-rwo |
| `apps-audiobookshelf/audiobookshelf-metadata` | 20Gi | 0.0019 | 0.0162 | 1 | 0.9838 | completed-media-small-rwo |
| `apps-authelia/authelia-config` | 1Gi | 0.0001 | 0.0003 | 0.25 | 0.2497 | completed-sqlite-next-rwo |
| `apps-bazarr/bazarr-config` | 100Gi | 0.0448 | 0.0652 | 0.25 | 0.1848 | completed-sqlite-next-rwo |
| `apps-bindery/bindery-config` | 4Gi | 0.0101 | 0.0245 | 0.25 | 0.2255 | completed-sqlite-next-rwo |
| `apps-bookstack/bookstack-config` | 100Gi | 0.0128 | 0.1003 | 0.25 | 0.1497 | final-single-owner-group |
| `apps-bookstack/bookstack-mariadb-data` | 100Gi | 0.0090 | 0.3000 | 1 | 0.7000 | final-single-owner-group |
| `apps-calibre/calibre-config` | 1Gi | 0.0115 | 0.0190 | 0.25 | 0.2310 | completed-calibre-arr-rwo |
| `apps-calibre/calibre-library` | 10Gi | 0.2263 | 0.2272 | 1 | 0.7728 | completed-calibre-arr-rwo |
| `apps-calibre/calibre-web-config` | 1Gi | 0.0015 | 0.0016 | 0.25 | 0.2484 | completed-calibre-arr-rwo |
| `apps-calibre/kavita-config` | 1Gi | 0.0308 | 0.0353 | 0.25 | 0.2147 | completed-calibre-arr-rwo |
| `apps-cleanuparr/cleanuparr-config` | 1Gi | 0.0033 | 0.0097 | 0.25 | 0.2403 | completed-sqlite-small-rwo |
| `apps-ddclient/ddclient-config` | 100Gi | 0.0000 | 0.0000 | 0.25 | 0.2500 | completed-batch2-rwo |
| `apps-docker-mailserver/docker-mailserver-mail-config` | 1Mi | 0.0001 | 0.0000 | 0.25 | 0.2499 | final-single-owner-group |
| `apps-docker-mailserver/docker-mailserver-mail-data` | 10Gi | 19.4706 | 22.2377 | 28 | 5.7623 | final-single-owner-group |
| `apps-docker-mailserver/docker-mailserver-mail-log` | 1Gi | 0.0027 | 0.0063 | 0.25 | 0.2437 | final-single-owner-group |
| `apps-docker-mailserver/docker-mailserver-mail-state` | 1Gi | 0.0193 | 0.0907 | 0.25 | 0.1593 | final-single-owner-group |
| `apps-duckdns/duckdns-config` | 100Gi | 0.0000 | 0.0000 | 0.25 | 0.2500 | completed-batch2-rwo |
| `apps-filebot/filebot-config` | 100Gi | 0.0065 | 0.0072 | 0.25 | 0.2428 | completed-filebot-inactive-rwo |
| `apps-filebot/filebot-output` | 100Gi | 0.0000 | 0.0000 | 0.25 | 0.2500 | completed-filebot-inactive-rwo |
| `apps-filebot/filebot-watch` | 100Gi | 0.0000 | 0.0000 | 0.25 | 0.2500 | completed-filebot-inactive-rwo |
| `apps-flaresolverr/flaresolverr-config` | 100Gi | 0.0000 | 0.0000 | 0.25 | 0.2500 | completed-batch2-rwo |
| `apps-homer/homer-config` | 1Gi | 0.0009 | 0.0008 | 0.25 | 0.2491 | completed-pilot |
| `apps-homer/homer-without-auth-config` | 1Gi | 0.0009 | 0.0008 | 0.25 | 0.2491 | completed-pilot |
| `apps-jellyseerr/jellyseerr-config` | 100Gi | 0.0026 | 0.0092 | 0.25 | 0.2408 | completed-sqlite-small-rwo |
| `apps-mailpile/mailpile-path1` | 20Gi | 5.6533 | 6.4459 | 9 | 2.5541 | final-single-owner-group |
| `apps-mailpile/mailpile-path2` | 1Gi | 0.0000 | 0.0000 | 0.25 | 0.2500 | final-single-owner-group |
| `apps-openbooks/openbooks-books` | 5Gi | 0.0000 | 0.0000 | 1 | 1.0000 | completed-batch3-rwo |
| `apps-openbooks/openbooks-logs` | 1Gi | 0.0001 | 0.0001 | 0.25 | 0.2499 | completed-batch3-rwo |
| `apps-profilarr/profilarr-config` | 100Gi | 0.4500 | 0.4693 | 1 | 0.5307 | completed-calibre-arr-rwo |
| `apps-prowlarr/prowlarr-config` | 100Gi | 0.0460 | 0.1577 | 0.25 | 0.0923 | completed-media-small-rwo |
| `apps-radarr/radarr-config` | 100Gi | 0.5437 | 0.5916 | 1 | 0.4084 | completed-calibre-arr-rwo |
| `apps-scrutiny/scrutiny-config` | 100Gi | 0.0000 | 0.0000 | 0.25 | 0.2500 | completed-media-small-rwo |
| `apps-scrutiny/scrutiny-influxdb` | 100Gi | 0.0022 | 0.1571 | 1 | 0.8429 | completed-media-small-rwo |
| `apps-smokeping/smokeping-config` | 100Gi | 0.0001 | 0.0000 | 0.25 | 0.2499 | completed-pilot |
| `apps-smokeping/smokeping-data` | 100Gi | 0.0368 | 0.0810 | 0.25 | 0.1690 | completed-pilot |
| `apps-sonarr/sonarr-config` | 100Gi | 0.3880 | 0.6823 | 1 | 0.3177 | completed-sonarr-ytdl-adguard-rwo |
| `apps-ubooquity/ubooquity-config` | 1Gi | 0.0047 | 0.0046 | 0.25 | 0.2453 | completed-batch3-rwo |
| `apps-uptime-kuma/uptime-kuma-config` | 1Gi | 0.0060 | 0.0145 | 0.25 | 0.2355 | completed-sqlite-small-rwo |
| `apps-youtubedl-material/youtubedl-material-appdata` | 100Gi | 0.0030 | 0.0037 | 0.25 | 0.2463 | completed-sonarr-ytdl-adguard-rwo |
| `apps-youtubedl-material/youtubedl-material-mongodb-data` | 100Gi | 0.4896 | 0.6918 | 1 | 0.3082 | completed-sonarr-ytdl-adguard-rwo |
| `apps-youtubedl-material/youtubedl-material-users` | 100Gi | 0.0000 | 0.0000 | 0.25 | 0.2500 | completed-sonarr-ytdl-adguard-rwo |
| `apps-zabbix/postgresql-data-zabbix-postgresql-0` | 5Gi | 5.5744 | 13.6149 | 18 | 4.3851 | final-single-owner-group |

### Observed database evidence

- `adguard-home`: `Other/unverified /opt/adguardhome/work/data/sessions.db`; `Other/unverified /opt/adguardhome/work/data/stats.db`.
- `audiobookshelf`: `SQLite /config/absdatabase.sqlite`.
- `bazarr`: `SQLite /config/db/bazarr.db`.
- `calibre-web`: `SQLite /config/gdrive.db`; `SQLite /config/app.db`.
- `kavita`: `SQLite /config/kavita.db`.
- `cleanuparr`: `SQLite /config/cleanuparr.db`; `SQLite /config/users.db`; `SQLite /config/events.db`.
- `profilarr`: `SQLite /config/data/profilarr.db`.
- `prowlarr`: `SQLite /config/prowlarr.db`; `SQLite /config/logs.db`.
- `radarr`: `SQLite /config/radarr.db`; `SQLite /config/logs.db`.
- `sonarr`: `SQLite /config/sonarr.db`; `SQLite /config/logs.db`.
- `ubooquity`: `Other/unverified /config/ubooquity-6.mv.db`.
- `uptime-kuma`: `SQLite /app/data/kuma.db`.
- `jellyseerr`: `/app/config/db/db.sqlite3`, WAL and SHM files observed.
- `calibre-library`: `/library/metadata.db` SQLite header confirmed.
- `scrutiny`: `/opt/scrutiny/config/scrutiny.db`; Influx directory includes `engine`, `influxd.bolt`, `influxd.sqlite`. Filenames alone do not prove every engine format.

Missing results are not evidence that an application is stateless. The bounded
inspection did not search media trees or enumerate all files. Bindery lacks the
shell used by the probe; its SQLite classification is upstream-source evidence.
