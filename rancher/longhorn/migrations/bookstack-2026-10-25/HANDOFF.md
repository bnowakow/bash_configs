# Sudo-session handoff: recover etcd/k3s before BookStack migration

## Debug follow-up — 2026-10-25 12:55 UTC

Read-only investigation found confirmed storage stalls on proxmox3: etcd
reported WAL `fdatasync` durations of **40.4136s at 12:45:17 UTC** and
**9.2977s at 12:50:25 UTC**. K3s lost controller leader-election leases and
exited with status 1; its restart counter subsequently reached **20**.
At 12:47 UTC, etcd peer connections to `10.0.0.72:2380` were refused;
the port later returned. These are observed failure mechanisms; the initiating
cause of the storage stalls and peer restarts is not established.

Both hosts showed substantial I/O pressure. On proxmox3 at 12:53 UTC,
`/proc/pressure/io` reported some avg10=52.00% and full avg10=21.01%;
ZFS `txg_sync` and filesystem users were observed waiting in kernel I/O paths.
`arc_prune` had high lifetime CPU usage; concurrent Rancher catalog Git work
and Longhorn activity were visible, but causation is not established.
Local ZFS reported healthy pools; NVMe SMART passed with zero media/data
integrity errors and zero error-log entries. NVMe temperature was 75 C,
with historical thermal transitions (not proof of current throttling).
Local memory available was 18 GiB and root filesystem free space 307 GiB.
The inspected recent local kernel journal showed no OOM or disk I/O errors.

At 12:54 UTC both etcd members had matching applied index **34682044**,
term **268**, with proxmox2-old leader. Both endpoint health checks committed
in about 8 ms. A repeat at approximately 12:55 UTC committed in about 4 ms;
both direct API `/readyz` endpoints returned `ok`, and local NRestarts
remained 20. This is a brief recovery observation, not proof that the underlying
problem is repaired. Local I/O pressure avg10 dropped to zero by the repeat.
BookStack and MariaDB were confirmed at zero replicas, with both transfer
helpers running without restarts at 12:54 UTC.

Peer access limitation: SSH as `sup` works using
`/home/sup/.ssh/id_rsa` and the existing `/home/sup/.ssh/known_hosts`.
Root SSH was denied with both existing root and sup RSA identities.
Peer `sudo -n` requires a password; `sudo -n -l` showed general sudo requires
authentication and the sole passwordless exception is `qm reset 600`.
The peer user cannot read system journals. Peer service status was readable:
k3s active/running, NRestarts **10**. Peer memory available was 8.9 GiB,
root filesystem free space 52 GiB. Peer root logs remain uninspected.

No service, workload, storage, Fleet, migration guard, or gate changes were made.
Migration remains paused pending owner validation and longer health observation.

Recorded **2026-10-25 12:44 UTC / 13:44 CET**.
Workspace: `/home/sup/code/bash_configs/rancher`.

## Requested scope for the sudo-enabled Codex

Restore control-plane health on **proxmox3 (10.0.0.50)** and
**proxmox2-old (10.0.0.72)**. Investigate root-owned k3s/kernel logs, etcd peer
connectivity/quorum, disk I/O latency and memory/OOM evidence. The current user
cannot read the system k3s journal. Both API endpoints have failed readiness;
10.0.0.72 explicitly reports `etcd` / `etcd-readiness` failures. Local k3s is
restarting: NRestarts increased from **15 to 18**, latest state `activating`.
No root cause or completed repair is claimed. Migration's restart guard also
saw unexpected EOF and connection-refused errors against 127.0.0.1:6443.

Useful initial read-only checks on both hosts:

```sh
sudo systemctl status k3s --no-pager
sudo journalctl -u k3s --since '2026-10-25 12:25:00 UTC' --no-pager
sudo journalctl -k --since '2026-10-25 12:25:00 UTC' --no-pager
sudo ss -tnp '( dport = :2380 or sport = :2380 )'
sudo df -h /var/lib/rancher/k3s
```

This is a two-voter etcd cluster; quorum requires both. Preserve etcd data and
storage. Do not reset/rebootstrap etcd, remove members, restore a stale snapshot,
disable fsync, force-detach storage or delete PVCs as a routine recovery step.
Report diagnosis and any changes. Avoid concurrent storage benchmarks/bulk I/O.

**Leave BookStack/MariaDB scaling, Fleet reconciliation and migration helpers to
the migration owner.** Another session scaled BookStack during this work. A
writer restart during copying can invalidate migration evidence. Restore API
health first; do not independently "fix" a deliberately scaled-zero workload.

## BookStack migration state: incomplete, final database cutover NOT done

The user approved BookStack migration, and Mailpile must remain last.
Last successful live inspection showed both Deployments at replicas **0**:

- `apps-bookstack/bookstack`: config reference
  `bookstack-config-longhorn-rwo` (**256Mi**, Longhorn RWO, two replicas).
- `apps-bookstack/bookstack-mariadb`: still references **original local**
  `bookstack-mariadb-data`, PV `nas-bookstack-mariadb-data`.
- Helpers: `bookstack-config-transfer-20261025` on proxmox2-old and
  `bookstack-db-transfer-20261025` on proxmox3. The latter mounts original DB
  read-only plus new target DB claim **1Gi** `bookstack-mariadb-data-longhorn-rwo`.
  The isolated target MariaDB was stopped cleanly after verification; helper
  containers remain alive to hold targets attached for backup.
- Old local PVCs `bookstack-config` and `bookstack-mariadb-data` remain Bound,
  annotated keep, PV reclaim Retain. **Old config PVC was NOT mounted and does
  not contain the formerly live config.**

The actual live `/config` was ~5MiB in the original container layer. Its 1,169
entries were archived and verified (SHA256, modes, ownership, symlinks), then
mounted persistently via Fleet. That config stage ran successfully with the
original DB before the DB migration phase. Source app image and chart unchanged.

The chart regenerated APP_KEY during reconciliation because its lookup checks
`bookstack-bookstack-secrets` while it renders `bookstack-secrets`. The original
key was preserved in **`apps-bookstack/bookstack-preserved-app-key`**, marked
keep, and explicitly referenced by app values. Runtime key hash matched the
original. Do not regenerate or remove that Secret. No secret values are in Git.
DB credentials were unchanged. The chart-generated unused key can still rotate;
it must not become the active app key again.

## Verified data vs unfinished backup gate

A fresh stopped copy transferred **309,476,550 bytes / 592 entries** at 4MiB/s.
Source/target file checksums passed. Isolated MariaDB **13.1.1** started and
stopped cleanly; all-database table checks passed; all **41 BookStack table
checksums matched the source**. First attempt's grep falsely matched the valid
`failed_jobs` table name; it safely resumed source workloads, then was corrected
and a fresh stopped copy replaced staging. Current evidence is from that retry.

The first temporary NAS Job `bookstack-precutover-nas-20261025` is Complete but
**selected zero volumes**: direct volume-group labels were overwritten by the
PVC-label synchronizer. It is NOT a successful backup. No fresh target NAS
backup/independent restore has passed yet. The script was corrected to label
PVCs, wait for synchronization, and use job suffix `-retry`, but API instability
blocked the retry before it started. Temporary RecurringJob
`longhorn-system/bookstack-migration-backup-20261025` remains.

## Local execution gates — do not bypass

Coordinator **PID 4025357**, command
`bash longhorn/migrations/bookstack-2026-10-25/migrate-database.sh`, is waiting
for `/tmp/longhorn-bookstack-originals/backup-and-restore-verified`.
**That gate file does not exist. Do not create it manually.** No final Fleet
cutover can proceed until verified backup/restore creates it.

`backup-and-restore.py` now also refuses to start while the private
`migration-paused-for-control-plane` marker exists. The restart watcher exited
fail-closed and left `concurrent-writer-detected` containing
`Guard could not verify stopped writers`. This represents an API monitoring gap,
not an observed writer restart. A subsequent full source recheck failed because
kubectl exec lost its API connection; do not assume the gap is safe.

Private evidence/backups (sensitive; never commit or paste contents):
`/tmp/longhorn-bookstack-originals/`, directory mode700, including:

- `config-before.tar`, `config-frozen.tar`, `config-manifest.json`.
- `database-before.sql` supplemental logical dump.
- `database-manifest.json`, `database-source-checksums.txt`,
  `database-target-checksums.txt`, `database-isolated-verification.txt`.
- `config-backup-manifest.json`, `db-backup-manifest.json`.
- `repository-files.json`, `deployments.json`, original PVC JSONs.
- `secrets-before.json`, `preserved-app-key.json`: private original credentials.
- `database-copy-verified`: intermediate verification only, NOT migration success.

## Resume criteria / ownership

After both APIs remain ready and k3s restart counts stop increasing, report back
to the migration owner. They must confirm both writers remain zero, compare
original source hashes/metadata with the stopped-copy manifest and inspect
replica/source-pod history. If changed or uncertain, discard only non-production
staging and take a fresh stopped copy; preserve original source.
Only after resolving/archiving the guard alert should the restart watcher be
restarted and the control-plane hold removed. Finish targeted native NAS backup,
restore both claims independently, verify files and isolated DB/table checks,
clean scratch volumes, then release the cutover gate. Final Fleet apply must
reference both Longhorn claims, retain the original APP_KEY, and validate actual
pod mounts, database/app rollout, Fleet BundleDeployment readiness and HTTPS.
The two original local PVCs must remain retained.

Do not run `/tmp/update-bookstack-docs.py` until actual migration success; it is
a prepared completion update. BookStack is currently partial/in-progress, not a
completed app. No commit/push is authorized by this handoff.

## Owner resume attempt — 2026-10-25 ~13:02 UTC

User requested resume. Initial checks returned both APIs ready, k3s active with
NRestarts 20, writers 0 and both helpers unchanged. Before any new copy or backup,
restart count rose to 21, then 22. API readiness failed again; one response included
`poststarthook/rbac/bootstrap-roles` failed, even while etcd checks in that same
response were OK. This is a symptom, not a root-cause determination. A new
read-only observation window has not established sustained readiness.

The existing control-plane hold and failed-read guard marker remain intact.
No guard/gate was cleared, no workload was scaled, and no backup/cutover was
started by this resume attempt. The old coordinator still waits on its absent
backup-and-restore gate. A successful stable window plus full source hash/
metadata revalidation is still required. Source/restore manifest reads have
been rate-limited to 4MiB/s for the next attempt; no rehash ran in this attempt.

### Resume-window outcome — 2026-10-25 ~13:09 UTC

The read-only observer reached NRestarts 23 and eventually measured 126 seconds
of both APIs ready without a restart. Immediately afterward, the required
pre-rehash API check failed with connection refused on 127.0.0.1:6443. Thus even
that stable window was transient. **No source rehash started, no hold/guard was
cleared, no new backup or cutover ran, and no workloads were scaled.** Root-level
control-plane/storage investigation remains required before another attempt.

## Debug update — 2026-10-25 ~13:18 UTC

Recovery did not hold. Local NRestarts reached **26**, peer NRestarts **13**.
At ~13:11 UTC both etcd health checks failed; peer was activating and refused
etcd connections. Peer I/O PSI reached some avg10=91.91%, full avg10=66.34%,
while memory pressure was near zero and available memory remained ~10 GiB.
Peer ZFS pool status was healthy. A later five-second dataset-counter sample
attributed ~4.465 MiB/s / 1386 read IOPS and ~0.848 MiB/s writes to the peer
root dataset. VM 601 (Transmission) and VM 700 (backup server) contributed
much less during that sample; their CPU usage alone does not identify the
I/O source. No VM was stopped or throttled.

The busy 18 GiB Longhorn volume is Zabbix PostgreSQL,
`pvc-885c02ea-0331-4c7e-9408-e07f7ac6ec70`. At ~13:15 UTC its engine reported
both replicas RW, no rebuild, and snapshot purges complete. An all-engine
check at 13:16 UTC found no active rebuild or purge. API readiness still
subsequently failed on etcd checks, so completion alone is not a verified fix.
No Longhorn settings or replicas were changed.

Started the existing read-only collector as transient systemd unit
`bookstack-control-plane-debug.service`, with RuntimeMaxSec=1800 (30 minutes),
UMask=0077, peer 10.0.0.72, output `/tmp/bookstack-control-plane-debug`, and
120-second capture cooldown. It samples existing metrics and captures host,
ZFS, process, kernel and network evidence on latency/Raft events; it does not
benchmark disks or change workloads. Use `journalctl -u
bookstack-control-plane-debug` and inspect that private directory for captures.
The prior `k3s-etcd-latency-monitor.service` was absent/inactive.

Peer system journal/root diagnostics remain blocked by sudo authentication;
sup SSH works. Migration holds, guards and gates remain untouched.

## Resume observation passed — 2026-10-25 13:30:58 UTC

Both direct API readiness endpoints passed every ~30 seconds from 13:20:32
through 13:30:58 UTC (626 seconds). Both k3s services stayed active, with
NRestarts unchanged at local **27** and peer **14**. Final etcd endpoint health
checks committed in 11.6 ms (local) and 6.7 ms (peer). No new local slow
fdatasync, leader-election-loss or service-exit entries appeared in that window.
Both BookStack Deployments remained at zero replicas and transfer helpers had
zero restarts. Local I/O pressure was low at the final check.

The migration owner can now attempt **source revalidation and guarded backup
work** using the existing resume procedure. This observation does not establish
that the underlying fault is repaired. Reconfirm readiness immediately before
work; fail closed on any renewed API gap or restart. Resolve the existing guard
alert through source hashes/metadata and history checks before removing the
hold or restarting the writer watcher. Backup/independent restore verification
is still required before cutover. No holds, guards, or gate files were changed
by this monitoring session. The watch script exited after the successful window.

## Owner resumed verification — 2026-10-25 ~13:27 UTC

User requested continuation after the debug update. Both APIs were ready with
local NRestarts 27. Full original-source hashes/metadata were revalidated at
4MiB/s and still matched the stopped copy; post-check APIs were ready, restart
count unchanged, and both writers zero. The old failed-read alert and
control-plane hold were archived after these checks. The writer guard restarted,
and targeted backup/independent-restore verification is running again. Final
cutover remains gated until those checks pass. See `ACTIONS.log` for timestamped
major actions; no underlying storage/control-plane repair is claimed.

## COMPLETED — owner final validation, 2026-10-25 ~13:40 UTC

BookStack migration finished. Both target volumes received fresh NAS backups;
both were independently restored and checked by hashes/metadata, isolated DB
startup/shutdown, all-database table checks and 41 source-matching table checksums.
Original source hashes were rechecked before cutover; no writer restart was
detected. Scratch restore/helper resources and temporary backup groups were
cleaned up. The gate released the coordinator, which applied final Fleet values.
Both actual app/DB pods now mount Longhorn claims, Recreate/one replica, Ready.
Both Fleet BundleDeployments are Ready with matching desired/applied IDs.
Both volumes have two healthy replicas on distinct nodes. SQL and HTTPS 200 work;
the original runtime and effective Laravel encryption key match. Other original
Opaque Secrets are unchanged, apart from the unused chart-generated app key.
Original local PVCs/PVs remain keep/Retain; private live-config/SQL backups remain.

The successful resumed run kept local k3s NRestarts 27 unchanged; this is not proof
that the underlying storage fault was repaired. The prior held coordinator and
writer/rollout watchers have exited successfully. No stale gate should be used
to rerun this one-time migration. See `RESULTS.md`, `ACTIONS.log`, updated current
storage inventory and remaining priority plan. Mailpile remains last.
