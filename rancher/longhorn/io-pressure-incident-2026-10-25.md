# Storage I/O incident — 2026-10-25

## Proxmox2-old expansion completed — 2026-10-25 19:35–19:36 CET / 18:35–18:36 UTC

User explicitly requested expanding this host after reading the 150GiB procedure
and the known reliability finding. Grew `rpool/longhorn` / `/dev/zd0` online
from **80 to 150GiB (161061273600 bytes)** at 18:35:36 UTC, then grew ext4.
Filesystem UUID `18ac8246-d16c-4dfd-873b-a53bc0348957`, Longhorn disk UUID
`ea436ad0-7d22-46b2-a5a6-e11519adf713`, disk key
`default-disk-7d27979faac45811`, mount path, ZFS refreservation 0 and Longhorn
reservation **8395570380 bytes / 7.82GiB** were preserved.
Commands/results: [local maintenance log](proxmox2-old-expansion-2026-10-25.log).

Preflight passed **600 seconds / 21 samples** of both direct APIs ready, k3s
active with restart counts unchanged at local **0** / proxmox3 **60**, and I/O
PSI avg10 below the documented 5% some / 2% full screening limits (local 0%,
peer maximum 0.03%). SMART temperature was 41 C, warning **0x04** persisted,
and thermal counters remained unchanged. Pool ONLINE, ext4 mounted rw, no
recent matching storage-error kernel messages in the bounded capture. All
39 production volumes had completed NAS backup records; existing restore
evidence was reviewed rather than claiming fresh restores of every backup.
The maintenance decision explicitly records failed SMART health and consumed
estimated endurance. It does not establish drive repair.

At **18:36:10 UTC**, Longhorn had reconciled the existing disk and reported:

| Node | Maximum GiB | Filesystem free GiB | Reserved GiB | Scheduled GiB | Nominal room GiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| proxmox2-old | 147.09 | 125.68 | 7.82 | 44.51 | 94.76 |
| proxmox3 | 147.09 | 122.56 | 0 | 47.27 | 99.82 |

Disk Ready/Schedulable and identities preserved. All **12 attached volumes**
were healthy and all **12 running engines** had two RW replicas. The five
previously documented detached production exceptions remained unchanged, with
their one nonfailed copy on proxmox3 and completed NAS backups. Mailpile staging
and native-test replica exceptions likewise remained unchanged. Local scheduled
capacity changed from 46.01 to 44.51GiB during background reconciliation; this
session did not remove replicas or change policy. Budget must be re-measured
after repairing those placements.

Post-grow I/O PSI avg10 was **0.06% some / 0.02% full**, local k3s restart
count remained zero, both APIs passed. Final ZFS interval write waits were
**51–171 microseconds** with no pending queues. SMART temperature was 42 C,
warning still **0x04**, thermal counters unchanged. Peer PSI was zero and
restart count remained 60. No reboot, service restart, workload restoration,
PVC resize, reservation change, replica repair or cap increase was performed.

**Physical NVMe space after expansion:** `rpool` is **236.00GiB**, allocated
**185.04GiB**, physically free **50.96GiB**. ZFS dataset-available space is
**43.66GiB**, a different figure after internal accounting. Root dataset uses
about **76.33GiB**, VM zvols **84.79GiB**, and the Longhorn zvol **23.90GiB**;
these accounting views need not sum exactly to pool allocation. A 20% pool
margin is **47.20GiB**, leaving only **3.76GiB further physical allocation
above that planning floor**. The sparse resize added virtual capacity; it
did not create 70GiB of physical free space. Do not admit migrations from the
125.68GiB filesystem-free figure alone. Drive replacement/capacity planning and
the migration admission hold remain; the earlier host-expansion hold was
superseded only for this explicitly requested, completed grow.

Private preflight/postflight inventory and stability samples:
`/tmp/proxmox2-expansion-preflight/`. No raw logs or secrets were committed.
The procedure and current/remaining capacity documents were updated.

## Additional proxmox3 buffer — 2026-10-25 19:14:34 CET / 18:14:34 UTC

User requested increasing the just-expanded local backing device from 128GiB to
**150GiB**. Grew the same zvol and ext4 online, retaining filesystem/disk UUIDs,
mount path and zero Longhorn reservation. The device now reports exactly
**161061273600 bytes**; Longhorn maximum is **147.09GiB**, physical free
**122.56GiB**, scheduled **47.27GiB**, nominal room **99.82GiB**.
Post-verification at approximately 19:15 CET confirmed Ready/Schedulable disk,
healthy attached volumes, two RW replicas on running engines, both APIs ready,
local k3s active with NRestarts unchanged at 60, near-zero local I/O PSI and
healthy ZFS pool. The interrupted verification was rerun read-only; the resize
itself was not repeated. Commands/results are appended to the same
[maintenance log](proxmox3-expansion-2026-10-25.log).
Peer capacity, its reliability warning and the previously recorded detached
replica exceptions are unchanged. Workloads remain deliberately stopped.

## Proxmox3-only host expansion — 2026-10-25 19:10:54 CET / 18:10:54 UTC

User explicitly requested proceeding on proxmox3 first despite the peer's
reliability warning. Expanded `rpool/longhorn` / `/dev/zvol/rpool/longhorn`
(`/dev/zd0`) from **100GiB to 128GiB**, then grew mounted ext4 online. No peer
resize, reboot, service restart, PVC size change, reservation change or cap
increase was performed. Full timestamped commands/results and final capacities:
[proxmox3-expansion-2026-10-25.log](proxmox3-expansion-2026-10-25.log).

Preflight: local Apacer SMART passed, warning `0x00`, temperature 54 C, no media
errors; local pool ONLINE with ~319GiB free, no quotas/reservations/snapshots
constraining the grow. Both APIs were ready and I/O PSI low. Production NAS
backup records were Completed. Contrary to the assumption that every volume
had two usable replicas, five detached production volumes had only one nonfailed
replica, on proxmox3: Homer config, Homer-without-auth config, Radarr config,
Bazarr config and OpenBooks books. Their backups were present. These exceptions
were disclosed before proceeding; no replica repair was attempted as part of
this local filesystem resize. Unverified Mailpile staging/test exceptions were
also recorded privately in the preflight inventory.

Post-verification: Longhorn maximum **125.43GiB**, physical free **100.88GiB**,
scheduled **47.27GiB**, reservation **0**, nominal room **78.16GiB**. Filesystem
UUID `1c430c03-1079-48d3-bd8c-9c4e11c1ce1c`, Longhorn disk UUID
`ad96e77f-516f-4f16-8dfe-c5c6eb4fb6d5`, disk key/path and reservation unchanged;
disk Ready/Schedulable. Both APIs passed; attached volumes were healthy and
running engines had two RW replicas; k3s NRestarts remained 60; local I/O PSI
was near zero; mail/DNS/auth pods were Ready. Private before/after inventory:
`/tmp/longhorn-proxmox3-resize-preflight-20261025/`.

**The peer expansion/incident hold remains.** Its failed SMART reliability
finding and detached replica exceptions still require follow-up. Earlier
"no expansion performed" statements below describe their historical timestamps.
Stopped applications were not restored by this maintenance.

## Broad shutdown completed — 2026-10-25 approximately 18:59 CET

User requested another retry. At **18:54 CET**, API access returned and the
coordinator saved an inventory of **30 eligible application controllers** before
scaling the non-database writers to zero. Six controllers were already at zero;
the restoration inventory preserves those zeros (Filebot must not be enabled
automatically). Fleet files were not edited. After all writers were verified
stopped, BookStack MariaDB, youtube-dl MongoDB and Zabbix PostgreSQL were also
scaled to zero. Final API verification found **all 30 controllers at desired
and current zero, with no active pods in their target namespaces**.

Durable, secret-free pre-batch replica counts:
[io-relief-replicas-before-2026-10-25.json](io-relief-replicas-before-2026-10-25.json).
Use those counts when planning restoration; earlier explicit stops remain in
effect. Restore databases and verify health before starting their application
writers. Fleet can reconcile these runtime overrides back to its desired state.
Protected mail, DNS, authentication and system/storage services were preserved.

The worker's initial writer verification incorrectly treated the omitted
zero-valued Scale `spec.replicas` field as unknown, causing a fail-closed wait.
The coordinator verified zero replicas against full controllers and actual pod
inventory, stopped the waiting worker, corrected the verifier to interpret the
omitted Scale value as zero, then completed the database scales explicitly.
The broad shutdown worker is **no longer running**.

At **18:56:58 CET**, I/O PSI avg10 was **0.18% some / 0% full on both hosts**;
both k3s services were active. Restart counts were local 60 and peer 0, indicating
the peer service counter had reset since the earlier investigation; no cause for
that reset is claimed here. Peer NVMe `temp1_alarm` read **0**. These are favorable
current observations but **do not clear the earlier failed SMART/degraded-NVM
reliability finding**. Obtain updated SMART and sustained health/replica/backup
checks before reassessing expansion. No storage expansion was performed.

## Fan intervention and workload relief — 2026-10-25 18:58 CET / 17:58 UTC

User opened the chassis and placed an additional fan over the NVMe. Passive
samples at 18:56:02 and 18:56:43 CET show a substantial thermal improvement:

- Composite temperature **49 → 48 C**, Sensor 1 **64 → 63 C**, compared with
  approximately 73–75 C / 93–95 C earlier.
- Critical Warning is now **0x04**: temperature warning cleared, **degraded
  NVM reliability remains**. SMART health still FAILED; Percentage Used 100%,
  media/data-integrity errors and error-log entries still zero.
- Thermal management counters stayed unchanged across the 41-second sample:
  level 1 transitions/time **1302 / 5483186 s**; level 2 **122 / 444078 s**.
  No active thermal-management time increase was observed in this short window.
- I/O PSI avg10 improved from **1.59% some / 0.66% full** to **0.02% / 0.01%**,
  and was **0.00% / 0.00%** at 18:57:54 CET. The longer averages were still
  decaying, so this is not a completed sustained-recovery screening window.
- ZFS interval write waits were **97 microseconds**, then **363 microseconds
  and 6 ms** in the later sample; sampled pending queues were zero.
- k3s was active/running with NRestarts=0 and local `/readyz` returned `ok`.
  Host uptime was only seven minutes; SMART power cycles increased 164 → 165
  and unsafe shutdowns 96 → 97. A reboot occurred between investigations;
  this agent did not initiate it. Do not attribute all recovery to the fan:
  reboot and workload reductions also changed the conditions.

Latest SMART capture: private `/tmp/longhorn-fan-smart-after.txt`. Earlier
`/tmp` evidence and the proposed retry worker from the fan-investigation
session were not present after reboot; do not assume those private captures or
that worker survived. That session's retry worker creation/execution was
interrupted and is not evidence of completed actions. The coordinating session's
separate broad shutdown outcome is recorded above.

User authorized steps 2–4 and subsequently broader application scale-downs.
The API recovered, enabling these additional runtime changes:

| Namespace | Controller | Before → after |
| --- | --- | --- |
| apps-zabbix | StatefulSet zabbix-postgresql | 1 → 0 |
| apps-youtubedl-material | Deployment youtubedl-material-mongodb | 1 → 0 |
| apps-bookstack | Deployment bookstack-mariadb | 1 → 0 |
| apps-mailpile | Deployment mailpile | 1 → 0 |

Before stopping the databases, live inventory confirmed Zabbix's three writer
Deployments, youtube-dl Material and BookStack at desired zero with no active
writer pods. At 18:57:55 CET none of these four namespaces had active or
terminating application/database pods; only the completed Zabbix nodesclean
Job pod remained. A blanket wait-for-delete timed out on that completed pod,
not on a running database. Database container exit codes were not collected;
scale-down used normal Kubernetes termination, without force deletion.

Earlier in this session watchdog Docker PostgreSQL was confirmed stopped with
exit **137** following the 60-second stop grace period; a clean shutdown was
not established. At 18:57:54 CET `docker ps` returned no running containers.

Many other optional applications were already at desired zero in the recovered
API inventory; this session cannot attribute those changes to its interrupted
requests. DNS, mail delivery, authentication, DDNS and cluster/storage/backup
infrastructure remain running. Fleet files were not changed; reconciliation
may restore runtime replica counts. Preserve all stop inventories when restoring.

**Assessment:** cooling clearly improved and current storage latency/pressure
are far better. The persistent reliability warning and consumed estimated
endurance still warrant disk replacement. Keep expansion on hold and restore
workloads deliberately only after sustained observation.

## Broader shutdown retry outcome — 2026-10-25 18:25:52 CET

The `/tmp/longhorn-scale-nonessential.py` worker exhausted its 15-minute retry
window and exited **2** before obtaining either API inventory. **No additional
replica changes were applied by this worker.** It is no longer running; no
restore inventory could be generated. Private progress log:
`/tmp/longhorn-nonessential-scale-down/actions.log`.
The completed earlier stops remain the only verified load-reduction changes
from this coordinating session. Additional application scale-down requires a
working Kubernetes API; do not infer shutdown from the user's authorization or
the existence of the worker script. Preserve the NVMe/thermal expansion hold.

## Broader application shutdown requested — 2026-10-25 18:12 CET

User authorized temporarily scaling down all nonessential application workloads
to relieve proxmox2-old. Runtime-only changes; Fleet files remain unchanged.
At 18:12 CET both API inventories and both direct etcd status checks failed.
**No additional scale-downs have yet been accepted by this new attempt.**

Retry worker `/tmp/longhorn-scale-nonessential.py` is bounded to 15 minutes.
It targets Deployments/StatefulSets in `apps-*` namespaces, excluding
`apps-docker-mailserver`, `apps-mailpile`, `apps-adguard-home`, `apps-authelia`,
`apps-ddclient`, and `apps-duckdns`. Cluster/storage/system namespaces are
untouched. It saves original replica counts to private
`/tmp/longhorn-nonessential-scale-down/original-replicas.json` before changes and
logs progress to `/tmp/longhorn-nonessential-scale-down/actions.log`.
Application writers must be confirmed at zero before database scale-downs.
Check the worker/log and actual resource state before starting overlapping work.
This retry does not directly kill containers or bypass unavailable Kubernetes
controllers; an API outage can leave the entire attempt unapplied.

At 18:08 CET Docker inspection confirmed watchdog application, watchdog
PostgreSQL and peer Scrutiny all exited. Watchdog PostgreSQL was now exit 137,
reported as stopped ~41 minutes earlier; this coordinating session did not
issue that PostgreSQL stop and has not established who/what stopped it.

## Local privileged investigation — 2026-10-25 17:13 CET / 16:13 UTC

Confirmed this session runs as root on `proxmox2-old.localdomain`. Read-only
collection completed; no workloads, services, storage or configuration changed.
Private raw evidence: `/tmp/longhorn-incident-20261025-local/` (not committed).
The earlier sections below preserve the original handoff and action inventory.

**New finding: the Patriot P300 reports failed SMART health, degraded NVM
reliability and active thermal management.** Firmware `EDFM90.1`, device
`/dev/nvme0n1`; the root pool uses its partition 3 and Longhorn mounts `/dev/zd0`.

| SMART field | 17:05:50 CET | 17:11:28 CET |
| --- | --- | --- |
| Critical Warning | `0x06` | `0x06` |
| Composite / Sensor 1 | 72 C / 92 C | 73 C / 93 C |
| Percentage Used | 100% | 100% |
| Available Spare | 100% | 100% |
| Media/data-integrity errors / error-log entries | 0 / 0 | 0 / 0 |
| Warning composite temperature time (minutes) | 7990 | 7996 |
| Critical composite temperature time (minutes) | 0 | 0 |
| Thermal management 1 transitions / total seconds | 1301 / 5483174 | 1301 / 5483174 |
| Thermal management 2 transitions / total seconds | 121 / 439945 | 121 / 440283 |
| Controller busy time (minutes) | 68866 | 68871 |

`smartctl -x` returned exit **8**, with explicit failed-health messages for
temperature and degraded subsystem reliability. `0x06` includes both warnings.
Percentage Used is a vendor estimate: 100% means estimated endurance consumed,
not proof of immediate failure; the separate reliability warning must still be
investigated. See [NVMe health field definitions](https://learn.microsoft.com/en-us/windows/win32/api/nvme/ns-nvme-nvme_health_info_log).
Reported composite warning/critical thresholds are 70/80 C. Sensor 1's own
threshold remains unknown.

Thermal management level-2 total time increased **338 seconds over 338 seconds**;
this establishes active thermal management during the comparison, rather than
historical counters alone. It strongly supports thermal performance limiting as
a contributor, but does not quantify its impact or establish the sole cause.
The mechanism behind the reliability warning remains unverified; zero media
errors does not negate that warning.

Concurrent evidence:

- At 17:05:47 CET, I/O PSI avg10 was **79.28% some / 50.46% full**.
- ZFS interval rows at approximately 17:05:41–44 CET showed **11–28 s total
  write waits**, **277–699 ms disk write waits**, and **559–724 pending async
  writes** at only about **0.9–2.2 MiB/s** write throughput. The since-boot row
  was excluded from these ranges. Pool status still reported healthy.
- k3s remained `activating/start`, restart count **8**, across the collector.
  At 17:06:45 CET API readiness failed etcd, etcd-readiness and RBAC bootstrap.
- The bounded kernel capture contains containerd-shim writeback waits exceeding
  **313–354 s** at 16:52:15 CET, a journald watchdog failure and restart, and a
  journal file described as corrupted or uncleanly shut down. That message does
  not by itself establish filesystem or media corruption.
- Repeated `ext4: Unknown parameter 'emergency_ro'` messages also occur during
  volume mount activity; their caller and relevance remain unverified. They do
  not establish a successful read-only remount.
- No physical NVMe reset/timeout, PCIe/AER, OOM or explicit media I/O error was
  found in the bounded kernel capture. The 1500-line cap and impaired logging
  mean this is not proof none occurred. Virtual iSCSI disk attachment messages
  mentioning resets are not evidence of a physical NVMe controller reset.

Capture limitations: the collector's 30-minute k3s journal timed out (exit 124),
as did a separate 20-second one-hour k3s journal request, leaving that latter
file empty. No new WAL-fsync timings could therefore be correlated. The kernel
request exited 0 but reached the 1500-line limit. Collector exit 0 only means
collection finished; individual failed checks above remain failures.

**Assessment / next steps:** this host has an actively thermally managed NVMe
reporting degraded reliability and severe storage stalls. Prioritize physical
cooling inspection and a drive replacement plan after checking independent
backups and replica recoverability. Keep the expansion hold and stopped-workload
inventory in effect. Cooling may reduce stalls but cannot be assumed to clear
the reliability warning; repeat SMART/latency/PSI/readiness measurements after
physical intervention. Do not remove this voter or reboot as an implicit next
step: the documented two-voter cluster requires coordinated recovery planning.

Recorded **2026-10-25 15:52 UTC / 16:52 CET**. Incident remains open.
This is an observation/action log, not a completed repair or expansion approval.
Times below are CET (UTC+1) unless explicitly marked UTC.

## Confirmed NVMe temperature alarm on proxmox2-old

At approximately **16:52 CET**, read-only sysfs inspection returned:

```text
/sys/class/hwmon/hwmon1/name = nvme
temp1_label = Composite
temp1_input = 73850
temp1_max   = 69850
temp1_crit  = 79850
temp1_alarm = 1
temp2_label = Sensor 1
temp2_input = 93850
```

Thus composite temperature was **73.85 C**, above the exposed **69.85 C high
threshold**, and the temperature alarm was asserted. The additional sensor
reported **93.85 C**. No limit was exposed for that additional sensor; do not
compare it directly with the composite channel's critical threshold.
The peer's previously inventoried root-pool device is a **Patriot M.2 P300
256GB**. The pool also backs the dedicated Longhorn zvol.

**Thermal throttling is a hypothesis, not a proven root cause.** The alarm and
high temperatures are confirmed; current throttling counters, peer SMART health,
and root-owned kernel logs have not been inspected. `temp1_alarm` maps to the
NVMe SMART temperature-warning bit in the [Linux NVMe hwmon driver](https://code.googlesource.com/linux/torvalds/linux/+/2656821f1f202d58224551b71eff41aafd1edf8b/drivers/nvme/host/hwmon.c).
Investigate cooling/airflow and obtain privileged SMART/kernel evidence before
declaring the drive healthy, failed, or repaired. Do not raise temperature limits
or disable write durability to suppress the symptoms.

## Handoff for sudo-enabled Codex on proxmox2-old — drive/kernel evidence

User requested documenting this read-only investigation for a separate Codex
session running **on proxmox2-old (10.0.0.72)**. Confirm the hostname before
collecting; this section does not authorize a reboot or configuration change.

**Task:** collect privileged NVMe SMART and kernel/k3s evidence to determine
whether thermal management, device errors/resets, or another storage problem
correlates with the observed severe I/O stalls. Preserve the original evidence
and report what is confirmed versus still uncertain.

Run in Bash, with authenticated sudo. Store raw logs privately, not in Git:

```bash
hostname -f
lsblk -o NAME,MODEL,SIZE,TYPE,MOUNTPOINTS
findmnt -T /var/lib/longhorn -o TARGET,SOURCE,FSTYPE,OPTIONS

umask 077
diagnostics_dir=$(mktemp -d /tmp/proxmox2-old-nvme.XXXXXXXX)
printf 'Evidence directory: %s\n' "$diagnostics_dir"
date -u +%FT%TZ > "$diagnostics_dir/started-utc.txt"

# /dev/nvme0n1 was the observed Patriot P300; confirm against lsblk above.
sudo timeout --kill-after=2 20 smartctl -x /dev/nvme0n1 \
  > "$diagnostics_dir/smart-before.txt" 2>&1
sudo timeout --kill-after=2 20 journalctl -k -b --since '1 hour ago' \
  -n 1500 --no-pager -o short-iso \
  > "$diagnostics_dir/kernel-journal.txt" 2>&1
sudo timeout --kill-after=2 20 journalctl -u k3s --since '1 hour ago' \
  -n 1500 --no-pager -o short-iso \
  > "$diagnostics_dir/k3s-journal.txt" 2>&1

systemctl show k3s -p ActiveState -p SubState -p NRestarts \
  > "$diagnostics_dir/k3s-state-before.txt"
cat /proc/pressure/io > "$diagnostics_dir/io-pressure-before.txt"
timeout --kill-after=2 10 zpool iostat -v -l -q 1 5 \
  > "$diagnostics_dir/zpool-latency.txt" 2>&1
timeout --kill-after=2 10 zpool status -xv \
  > "$diagnostics_dir/zpool-status.txt" 2>&1

# A second read allows comparison of thermal/error counters without a benchmark.
sleep 60
sudo timeout --kill-after=2 20 smartctl -x /dev/nvme0n1 \
  > "$diagnostics_dir/smart-after.txt" 2>&1
cat /proc/pressure/io > "$diagnostics_dir/io-pressure-after.txt"
systemctl show k3s -p ActiveState -p SubState -p NRestarts \
  > "$diagnostics_dir/k3s-state-after.txt"
date -u +%FT%TZ > "$diagnostics_dir/finished-utc.txt"
```

Check command exit status when running; a timeout or empty/partial file is **not**
evidence of a healthy drive. If `smartctl` is missing, record that and use already
installed read-only NVMe tooling if available; do not automatically install or
upgrade packages during this incident. Do not start a SMART self-test.

Inspect/report:

- Exact model, firmware, temperature channels, warning/critical thresholds, and
  SMART critical-warning flags. Compare with the sysfs alarm above. Sensor 1's
  own limit is unknown; do not apply the composite threshold to it.
- Warning/critical temperature time, thermal-management transition counts and
  total time, comparing both SMART captures. Increasing counters are stronger
  evidence than historical nonzero counters; absence of exposed counters does
  not rule out thermal effects.
- Media/data-integrity errors, available spare, percentage used, error-log
  entries, controller busy time, and whether error counters increased.
- Kernel messages for NVMe timeout, controller reset, aborted I/O, PCIe/AER
  errors, filesystem errors, hung tasks, OOM, and read-only remounts. Preserve
  the full bounded journal capture; do not retain only matching lines.
- Correlation with k3s WAL-fsync delays, lost leadership/restarts, I/O PSI and
  actual interval queue/latency rows. The first `zpool iostat` row is since boot.

Append a timestamped **summary** and the private evidence directory to this log.
State whether thermal management was observed actively increasing, whether
device/kernel errors were present, and which facts remain unverified. Do not
commit raw logs, environment variables, kubeconfigs or Secrets. The broader
[host collector](collect-host-storage-diagnostics.sh) is also available if this
checkout contains it; the focused commands above cover the requested point 2.

**Leave workload scaling to the coordinating session.** Several applications
are deliberately stopped and another scale-down retry may be active (see below).
Do not restart them, alter Fleet, force-detach volumes, reduce replicas, reset
etcd, run a disk benchmark, run filesystem repair, change thermal limits/fsync,
or resize storage as part of evidence collection. Report back before proposing
changes; no root cause or repair is established by the current alarm alone.

## Symptoms and observed trend

- Both k3s servers repeatedly lost controller leadership and restarted; both
  APIs repeatedly failed etcd readiness. This is a two-voter etcd cluster:
  both voters are required for quorum.
- Earlier proxmox3 WAL flushes took **40.4 s** and **9.3 s**. Its local ZFS pool
  reported healthy and NVMe SMART showed zero media/data-integrity errors in
  that earlier inspection. That does not establish peer SMART health.
- Before the peer reboot, SSH/Tailscale sessions and the Proxmox web service
  intermittently stalled even while LAN ping and TCP port 22 responded.
- User issued `sudo halt`, then reported rebooting/powering the peer back on.
  At **16:12 CET**, LAN SSH worked and peer uptime was about two minutes.
  The agent did not reboot either host. Proxmox3 was left running.
- The peer reboot did **not** produce sustained recovery. Its k3s restart
  count subsequently reached **8** by approximately **16:50 CET**. Proxmox3's
  last observed count in this period was **47**.
- Peer I/O PSI repeatedly reached **90–100% some** and **70–97% full**.
  Low available throughput did not mean the disk was healthy: interval samples
  showed approximately **5,000 synchronous writes queued**, **25 s total write
  waits**, and later **14 s waits with ~687 writes queued**.
- At **16:38 CET**, peer pressure briefly improved to **21.72% some / 13.19%
  full**, queues drained, and interval write waits were approximately
  **0.7–11 ms**. At **16:39 CET**, pressure was near zero, but k3s restarted.
  Heavy pressure returned afterward. Do not treat that brief window as repair.
- Around **16:51 CET**, a five-second ZFS dataset-counter sample showed only
  ~321 KB/s root-dataset reads and ~3.3 KB/s Longhorn zvol writes while the peer
  remained under severe pressure. Queues, latency, temperatures and throughput
  must be assessed together. Peer `zpool status -xv` reported healthy; this
  does not rule out latency or thermal problems.

For `zpool iostat`, the first row is a since-boot average; interval rows supplied
the short-window queue/latency measurements above. PSI percentages describe time
tasks are stalled, not disk bandwidth utilization.

## Completed load-reduction actions — restore deliberately

User explicitly authorized the following runtime-only stops. **Fleet files were
not edited.** Kubernetes changes can be reverted by Fleet reconciliation.

| Host | Workload | Confirmed action/status |
| --- | --- | --- |
| proxmox2-old | Docker `home-assistant-watchdog-springboot-1` | Stopped; exit 143 confirmed. |
| proxmox2-old | Docker `scrutiny` | Stopped; exit 0 confirmed. |
| proxmox3 | Docker `nubile` | Stopped; exit 0 confirmed. |
| proxmox3 | Docker `emby` | Initially retained, then stopped on subsequent user instruction; exit 0 confirmed. |
| proxmox3 | `apps-sonarr/deployment/sonarr` | Direct k3s scale to 0. |
| proxmox3 | `apps-radarr/deployment/radarr` | Direct k3s scale to 0. |
| proxmox3 | `apps-bazarr/deployment/bazarr` | Direct k3s scale to 0. |

The three media scale requests were accepted before their pods actually stopped.
At approximately **16:43 CET**, all three Deployments were confirmed at desired
0 with no current replicas, and the local CRI inventory confirmed no running
Sonarr/Radarr/Bazarr containers. Earlier reports of accepted scaling alone were
not evidence that their disk activity had stopped.

Watchdog PostgreSQL (`home-assistant-watchdog-postgres-1`) was intentionally left
running in this batch. youtube-dl Material/MongoDB, mail, DNS, Longhorn, etcd,
k3s and Proxmox services were not stopped by these completed actions.

Local Emby reads measured ~3.2 MiB/s in one sample, but its media is NFS-backed;
its config is on the local root pool. This sample does not prove Emby caused
local-pool stalls. CPU percentages and cumulative Docker block-I/O totals likewise
do not establish which workload caused the peer's queue buildup.

Stopping these workloads did not establish sustained recovery. Proxmox3 was often
quiet afterward; the peer continued to experience severe stalls, and both hosts
still had intermittent restarts/API failures.

## Next scale-down batch — pending, not completed

User subsequently authorized continuing incremental application scale-downs and
measuring the effect. At this log's timestamp, the API had **not accepted** the
following next batch:

- `apps-youtubedl-material/deployment/youtubedl-material`
- `apps-zabbix/deployment/zabbix-zabbix-server`
- `apps-zabbix/deployment/zabbix-zabbix-web`
- `apps-zabbix/deployment/zabbix-zabbix-webservice`

Retry worker: `/tmp/longhorn-scale-io-batch.py`, invoked with Python 3. It retries
for at most 15 minutes and targets only those four Deployments through their
Scale subresources. It records pre-change replica counts and accepted updates
in private `/tmp/longhorn-io-relief-actions.jsonl` when API reads succeed.
Check that log, the worker process and actual workloads before assuming success
or starting another worker. It does not alter Fleet.

MongoDB and Zabbix PostgreSQL have **not** been stopped in this batch. Confirm
their application writers are stopped before any later graceful DB scale-down.
No subsequent library-app batch has been applied at this timestamp.

## Monitoring, evidence and expansion hold

- `/tmp/longhorn-expansion-watch.py` continuously checks both direct APIs,
  k3s state/restart counts and both hosts' I/O PSI every ~30 seconds. Its
  conservative screening window requires 10 continuous minutes with APIs ready,
  stable restart counts, and each host below 5% `some` / 2% `full` avg10 I/O PSI.
  These are local screening criteria, not vendor safety guarantees or proof of
  root-cause repair. A passing window still requires backup, replica, temperature
  and storage-inventory review before any resize.
- Existing read-only collector was run as transient
  `bookstack-control-plane-debug.service` with a 30-minute maximum lifetime.
  Private captures: `/tmp/bookstack-control-plane-debug/`. This service must not
  be assumed to still be running. The first capture at **14:17:26 CET** included
  local writes of ~66–73 MiB/s, elevated I/O PSI, and no ping loss to the peer.
- Reusable root diagnostic collector:
  [collect-host-storage-diagnostics.sh](collect-host-storage-diagnostics.sh).
  Local smoke-test output was written privately to
  `/tmp/longhorn-host-diagnostics.fURNfMd7/`.
- Peer SSH as `sup` works intermittently. General sudo requires authentication;
  root SSH was denied. Peer system journals and SMART need an authenticated sudo
  session. Existing Docker permissions permit the explicitly requested Docker
  stops; they have not been used to obtain host-root access.

**Host expansion remains blocked.** No zvol/filesystem/PVC resize, reservation
change, replica-count reduction, fsync change, datastore reset, volume deletion,
or forced storage detach was performed by this investigation.
See [expansion procedure](README-4-expand-storage.md). BookStack migration did
complete earlier; its migration success is not proof this later incident is fixed.

Before restoring stopped services, record their current state and restore them
in small groups, comparing temperatures, I/O latency/queues, PSI, replicas and
API readiness after each group. Preserve this runtime-stop inventory so the
services are not forgotten after maintenance.
