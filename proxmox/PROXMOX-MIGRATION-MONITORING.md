# Proxmox migration monitoring

Use these scripts to capture evidence while moving VM 700 back to this node. They are passive collectors: they do not issue disk tests, restart services, or alter the migration.

Before the migration, confirm that `sysstat` is installed so `iostat` can report per-disk latency, utilisation, and queue depth:

```bash
apt-get update && apt-get install sysstat
```

In one root shell on the destination node, start monitoring and leave it running:

```bash
cd /home/sup/code/bash_configs/proxmox
./monitor-proxmox-vm-migration.sh -v 700 -i 2
```

It prints the new log directory, normally under `/var/log/proxmox-migration-monitor/`. Start the migration in a second shell or the Proxmox UI. Stop the monitor with `Ctrl-C` only after the migration has completed or the host is clearly no longer responding.

If the host freezes and is rebooted, run this immediately after it returns:

```bash
./capture-proxmox-migration-postmortem.sh
```

The monitor has the following files:

| File | What it helps identify |
| --- | --- |
| `iostat.log` | High `await`, `%util`, or queue depth on a specific disk/path |
| `zpool-iostat.log` | ZFS vdev throughput and saturation |
| `zpool-events.log` | ZFS I/O, checksum, device, and pool-state events emitted during the migration |
| `zfs-kstats.log` | Raw ARC and transaction-group (`txgs`) samples; long sync/write times or stalled TXGs point to ZFS/pool contention |
| `diskstats.log` | Raw kernel per-block-device counters, retained to calculate I/O and busy-time deltas if other tools stop reporting |
| `pidstat-disk.log` | Per-process read/write activity, useful for identifying competing VM or host workloads |
| `nvme-health.log` | NVMe SMART temperature/health and controller error-log snapshots every `interval × 30` seconds; an 8-second timeout is itself evidence of an admin-path stall |
| `pcie-aer-counters.log` | PCIe Advanced Error Reporting counters, including correctable errors that may not appear as kernel messages |
| `thermal.log` | `lm-sensors` readings every `interval × 30` seconds, when `sensors` is installed |
| `ceph.log` | Slow OSD operations or a degraded Ceph cluster, when Ceph is installed |
| `system.csv` | Load, available memory, dirty/writeback pages, and Linux pressure-stall metrics |
| `processes.log` | `D`-state blocked tasks and the QEMU/migration process state |
| `network.log` | NIC errors/drops and migration SSH/TCP socket state |
| `kernel-follow.log` | I/O resets, filesystem errors, NMI/soft-lockup, OOM, and driver faults |
| `proxmox-services-follow.log` | Errors emitted by Proxmox services |

When a freeze happens, copy the entire matching monitor directory and the postmortem directory before repeating the test. The key timestamps are ISO-8601 with timezone offsets, so events can be correlated directly across the logs.

The monitor does not repeatedly invoke `zfs list`, `zpool status`, SMART self-tests, or a scrub: those operations may themselves block on an unhealthy pool. Its bounded NVMe health query is read-only and runs only once per `interval × 30` seconds.


## Host-specific incident: proxmox5, 2026-10-01

For NIC monitoring on **proxmox5**, run:

```bash
sudo ./monitor-proxmox-nic.sh -n nic0 -i 5
```

`nic0` is the physical interface configured in this host's `vmbr0`. Stop monitoring with Ctrl-C; see the dedicated NIC monitor section below for log details and optional peer probes.

These findings and the applied mitigation concern **proxmox5 only**. The **proxmox2-old** investigation below instead shows severe NVMe/ZFS write stalls, failed SMART health, and temperature warnings. The hosts probably have different root causes; keep separate incident timelines, hardware inventories, kernel versions, and capture directories. Neither investigation establishes a common cause.

Evidence directory: `/var/log/proxmox-migration-monitor/proxmox5-postmortem-20261001T085319Z`. The directory suffix is UTC; the journal times below are local Europe/Warsaw time (CEST, UTC+02:00).

| Local time | Observation |
| --- | --- |
| 07:06:21 | Corosync loses links to both other cluster nodes. |
| 07:06:22 | First `e1000e 0000:00:1f.6 nic0: Detected Hardware Unit Hang`. |
| 07:07:13 | Cluster jobs start reporting no quorum. |
| 07:09:53 | First NFS server-not-responding timeout. |
| 10:46:30 | Last captured message still reports the NIC hang. |
| 10:47:31 | Current boot journal starts following the manual reset. |

The previous boot contains 6,605 NIC-hang messages. The first and last reports have the same transmit queue values (`TDH ec`, `TDT 45`, `next_to_use 45`, `next_to_clean eb`), consistent with a stuck transmit queue. The host continued running enough to write logs for roughly 3 hours 40 minutes after connectivity failed. This strongly supports a NIC transmit stall causing loss of management access, cluster quorum, and NFS access; it does not establish a complete CPU/kernel freeze or that a migration triggered this outage.

Hardware: HP EliteDesk 800 G6 Desktop Mini; Intel I219-LM (`8086:0d4c`), `nic0`, PCI `0000:00:1f.6`, driver `e1000e`. Both the failed and current boots use `7.0.14-19-pve`. Proxmox reports 9.2.21 and ZFS 2.4.4-pve1. `nic0` is the sole physical port configured in management bridge `vmbr0`.

No OOM, blocked-task warning, or disk I/O error was found in the captured previous-boot journal. After reboot, `rpool` was ONLINE with zero reported read/write/checksum errors and no known data errors. Post-reset pool health does not exclude a transient storage fault. No matching live-monitor directory was present under the capture root.

Current boot messages also include `Reset blocked by ME` and `PHY reset is blocked due to SOL/IDER session`. Investigate Intel AMT/Management Engine ownership or sessions if failures recur; these messages alone do not establish the cause or explain the absence of recovery.

### Mitigation applied on proxmox5

On 2026-10-01, the following runtime change was applied successfully and verified with `ethtool -k nic0`:

```bash
sudo ethtool -K nic0 tso off gso off
```

`tcp-segmentation-offload` and `generic-segmentation-offload` are now off. GRO, checksumming, and scatter/gather were left as they were. This is a diagnostic experiment, not a proven fix for this controller/kernel. Moving segmentation into software can increase CPU usage. Record whether the hang recurs under comparable traffic and while idle.

#### TSO/GSO follow-up, 2026-10-03

The October 1 NIC capture initially showed **TSO on and GSO on** under kernel `7.0.14-20-pve`, so the earlier runtime mitigation was no longer active. The settings were reapplied on October 1 at approximately **18:45 CEST** using `ethtool -K nic0 tso off gso off` and verified immediately. The collector recorded both off before its 18:45:54 shutdown; the next capture began at 18:45:58 with both off.

On **2026-10-03 at approximately 17:44 CEST**, a live `ethtool -k nic0` check confirmed **TSO off and GSO off**. All subsequent settings samples in the reviewed captures also showed both off. GRO remained on.

Review of the four NIC captures through October 3 at approximately 17:47 CEST found no recurrence of the hardware-unit hang over roughly **47 hours after reapplication**. RX/TX hardware errors and TX timeouts remained zero, the link stayed at 1 Gb/s full duplex without recorded carrier transitions, and heartbeats remained regular. This is encouraging observational evidence, not proof of a fix: no peer probes were configured, and comparable migration load was not established. The kernel had also changed from the incident's `7.0.14-19-pve` to `7.0.14-20-pve`.

The change is **not persistent**. Recheck after reboot or driver reload. If it proves useful, add the following to the existing `iface nic0 inet manual` stanza in `/etc/network/interfaces` on **proxmox5 only** during a planned network-maintenance window:

```text
    post-up /usr/sbin/ethtool -K nic0 tso off gso off
```

The persistent edit was applied on October 10; see the recurrence follow-up below. To reverse the runtime experiment to its observed original settings:

```bash
sudo ethtool -K nic0 tso on gso on
```

The mailing-list message was retrieved successfully with `curl`. It quotes an Intel developer recommending TSO disabling for transmit hangs in some e1000e configurations. The discussion concerns a PCH2 device, not this host's I219-LM, and does not specifically recommend disabling GSO. It supports testing TSO disabling, but does not prove a shared hardware bug or a fix for proxmox5. GSO disabling remains an additional experimental change: https://lists.osuosl.org/pipermail/intel-wired-lan/Week-of-Mon-20190520/016133.html

### Monitoring to narrow down the cause

1. Use a local console or an independent management path during the next incident. If the console responds while SSH/UI fail, inspect NIC counters and kernel messages before resetting. If the console is also unresponsive, capture console output and consider serial console or kernel crash capture as a separate investigation.
2. From another machine, timestamp continuous probes to this host, the NAS, and other cluster nodes. Correlate these with switch-port counters, link events, CRC errors, and drops. Probes distinguish host isolation from a NAS or wider network outage, but do not prove a CPU freeze.
3. Save NIC identity, offload settings, EEE, pause settings, and driver statistics before each test. Periodically sample `ethtool -S nic0` alongside `ip -s link`. The current postmortem script saves only `ip -s link`, so these additional snapshots are valuable.
4. Run the existing resource/storage monitor on both migration endpoints when available, and retain the source migration task log. The migration monitor was absent during the initial investigation but is now present in this checkout. It remains useful for resource/storage evidence, especially the independent proxmox2-old investigation.
5. Keep logs on local storage, not the affected NFS mount. Remote kernel logging via netconsole can preserve evidence when local writes fail, but it needs an independent healthy NIC to remain useful during a nic0 failure: https://www.kernel.org/doc/html/latest/networking/netconsole.html

For a standalone NIC collector on **proxmox5**, run this in a root local-console shell. Stop with Ctrl-C; it does not change NIC settings:

```bash
node=$(hostname -s)
logdir="/var/log/proxmox-migration-monitor/${node}-nic-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -m 0700 "$logdir"
for query in '-i' '-k' '--show-eee' '-a'; do
    timeout -k 2s 5s ethtool "$query" nic0
done > "$logdir/nic-baseline.log" 2>&1
while true; do
    date --iso-8601=seconds
    timeout -k 2s 5s ethtool -S nic0
    timeout -k 2s 5s ip -s link show dev nic0
    sleep 5
done >> "$logdir/nic-counters.log" 2>&1
```

In another root console, keep kernel messages in the same chosen log directory, or use `journalctl -kf -o short-precise` to watch them live. Collector timeouts are themselves useful evidence; no userspace timeout can guarantee termination of a task stuck in uninterruptible kernel sleep.

For **proxmox2-old**, first identify the actual interface/driver with `ip -br link`, `lspci -nn`, and `ethtool -i <interface>`. Collect the previous boot and the same resource evidence without assuming e1000e is involved.

### Further mitigation experiments, if the hang recurs

Change one variable at a time and record host, timestamp, settings, workload, and outcome. The only experiment already applied is TSO/GSO disabling on proxmox5.

- Reduce migration bandwidth and run one migration at a time. A starting trial on a 1 Gb/s path is `--bwlimit 30000` (KiB/s), set on the migration command on the source host. This can reduce load and preserve headroom, but is not a guaranteed NIC fix. Proxmox documents bandwidth and migration-network options: https://github.com/proxmox/pve-docs/blob/master/generated/qm.1-synopsis.adoc
- If TSO/GSO disabling is insufficient, try `sudo ethtool -K nic0 gro off` as a separate experiment; reverse with `gro on`. This is exploratory, with a possible CPU/throughput cost.
- EEE currently reports enabled but inactive, with no link-partner advertisement. `sudo ethtool --set-eee nic0 eee off` is a possible separate power-management experiment, with weak evidence here because EEE was inactive when checked. It may renegotiate the link; use console access and a maintenance window. Restore with `eee on` if appropriate.
- TX and RX pause are already off, so disabling pause is not an additional mitigation under the observed settings.
- Compare a previously installed `6.17.13-21-pve` kernel during planned maintenance, if it remains bootable and compatible with the host's installed ZFS modules. This is an A/B diagnostic for a possible regression, not evidence that 7.0 is responsible.
- Investigate BIOS/Intel ME firmware and AMT/SOL/IDER configuration against vendor guidance. Avoid disabling management access blindly; firmware or AMT changes require a planned maintenance window.
- Test a known-good alternative physical NIC/path. Separating migration traffic from cluster/management traffic can reduce the impact of a NIC stall. A separate VLAN on the same failed physical NIC does not provide this isolation.

Avoid automatic link bouncing or driver reload as the first response: nic0 currently carries management, bridge traffic, and cluster connectivity. If a hang recurs, preserve logs first and attempt recovery from a local console during a maintenance window.


### Dedicated NIC monitor

`monitor-proxmox-nic.sh` supplements the resource/storage migration monitor. Use it for the **proxmox5 network-controller investigation**; it does not assume proxmox2-old has the same fault. It never changes offloads, resets the link, or runs stress tests. Optional probes send one ICMP request per target per sample using host routing, not a forced physical-interface path.

Run from a root local console, optionally adding numeric IPs for the gateway, NAS, and another cluster node:

```bash
sudo ./monitor-proxmox-nic.sh -n nic0 -i 5
# Add each known peer with: -p <numeric-IP>
```

The default directory is `/var/log/proxmox-migration-monitor/<host>-nic-<UTC timestamp>`. Keep this on local storage. Start before a migration and also observe idle periods; stop with Ctrl-C. Logs grow until stopped, so use a bounded observation window and watch local free space.

| File | Evidence |
| --- | --- |
| `nic-baseline.log` | Boot ID, kernel, addresses/routes, driver, offloads, EEE and pause settings |
| `nic-counters.log` | Timestamped driver statistics, kernel link counters, negotiated link state and carrier transitions |
| `nic-settings.log` | Offload/EEE/pause snapshots every 12 iterations to detect setting changes |
| `heartbeat.log` | Uptime, load and pressure samples showing continued local execution after connectivity loss |
| `kernel-follow.log` | Current-boot kernel messages followed through the incident |
| `probes.log` | Optional peer responses and command exit statuses |
| `monitor-events.log` | Clean shutdown time and status |

External queries have a five-second timeout and two-second kill grace; their exit statuses are retained. Sampling interval is a pause after collection, so slow commands lengthen the period. These bounds cannot force a task out of uninterruptible kernel sleep. Unsupported ethtool queries are retained as errors rather than stopping collection. A heartbeat stopping does not itself prove a CPU freeze: local disk or the collector can also stall. Use an independent console and external probes to interpret it.

On proxmox2-old, continue using `monitor-proxmox-vm-migration.sh` for NVMe/ZFS/resource evidence. Run the NIC companion there only if network evidence warrants it, supplying that host's actual physical interface. No monitor is automatically started or installed as a service.

## Host-specific incident: proxmox2-old, 2026-09-29

Investigation on 2026-10-01 reviewed all five September 29 migration-monitor runs under `/var/log/proxmox-migration-monitor/`: `proxmox2-old-20260929T131037Z`, `proxmox2-old-20260929T132410Z`, `proxmox2-old-20260929T132909Z`, `proxmox2-old-20260929T133021Z`, and `proxmox2-old-20260929T153752Z`. Directory suffixes are UTC; times below are CEST (UTC+02:00).

The strongest suspect is the **Patriot M.2 P300 256GB NVMe SSD**, serial `BF5507290E3E00408055`, firmware `EDFM90.1`, controller `/dev/nvme0`. Its namespace EUI is `6479a76b5a300f9d`; partition `/dev/disk/by-id/nvme-eui.6479a76b5a300f9d-part3` is the **only device in `rpool`**, which backs the host root filesystem and VM 700's migration destination. The monitored kernel was `7.0.14-19-pve`; the October 1 SMART query ran under `7.0.14-20-pve`.

### Recorded storage stalls and temperature warnings

| Local time | Evidence |
| --- | --- |
| Sep 26 21:50:42 | smartd already reports `Critical Warning (0x04): Reliability`, before the September 29 monitored migrations. |
| Sep 26 22:09:39 | smartd reports `0x06`: Temperature and Reliability. The supplied notification identifies this as its original notification time. |
| Sep 27 00:10:49 | ZFS `ereport.fs.zfs.deadman` identifies a stalled physical write on the same NVMe partition. This is historical evidence retained in the September 29 `zpool-events.log`, not a new September 29 event. |
| Sep 29 15:24:23 | `iostat.log`: NVMe write latency `1002.32 ms`, throughput `1.60 MB/s`, queue depth `20.55`, utilisation approximately 100%. |
| Sep 29 15:40:23 | NVMe write latency `1527.96 ms`, throughput `1.58 MB/s`, queue depth `19.79`, utilisation `98.61%`. |
| Sep 29 18:57:33 | NVMe write latency `1676.88 ms`, throughput `1.59 MB/s`, queue depth `21.80`, utilisation `100%`. |
| Sep 29 15:31, 18:01, 18:31, 19:01 | smartd samples report `0x06` during the monitoring periods, supporting temperature stress alongside the persistent reliability warning. These are periodic samples, not exact threshold-crossing times. |

`processes.log` shows blocked ZFS transaction and I/O waits (`dmu_tx_wait`, `cv_wait_common`, and `txg_sync`), including `zfs recv -F -x encryption -- rpool/data/vm-700-disk-2`. Full I/O pressure (`io_full_avg10`) peaks at 80.09%, 83.24%, 90.28%, and 88.51% across the four affected runs, despite roughly 15–16 GiB of available memory and zero memory pressure at those peaks. The short 15:29 run has much lower full I/O pressure (1.28%). This supports a storage bottleneck affecting the whole host rather than memory exhaustion.

When parsing these `system.csv` files, account for the unquoted decimal comma in `date -Ins` timestamps: it adds an extra CSV field before the load values. A naive CSV parser shifts the metric columns and produces incorrect pressure and memory readings.

### SMART health checked on 2026-10-01

Read-only `smartctl -x /dev/nvme0` at approximately 11:46 CEST reported:

| Reading | Value |
| --- | --- |
| Overall SMART health | **FAILED — NVM subsystem reliability has been degraded** |
| Critical warning | **0x04 — Reliability** |
| Percentage used | **100%** (estimated rated endurance consumed) |
| Available spare / threshold | 100% / 5% |
| Lifetime data written / read | 226 TB / 278 TB |
| Power-on hours | 33,323 |
| Composite temperature | 62°C |
| Temperature sensor 1 | 80°C |
| Composite warning / critical thresholds | 70°C / 80°C |
| Accumulated composite warning-temperature time | 7,660 minutes |
| Accumulated composite critical-temperature time | 0 minutes |
| Thermal management transition counts, levels 1 / 2 | 1,270 / 103 |
| Media and data integrity errors / error-log entries | 0 / 0 |

The composite thresholds apply to the composite temperature, not necessarily to sensor 1. The `0x04` bit means the controller reports degraded reliability due to significant media-related or internal errors; it does not identify the specific failure mechanism. See the [NVMe 1.3a specification, SMART / Health Information Log](https://www.nvmexpress.org/wp-content/uploads/NVM-Express-1_3a-20171024_ratified.pdf). Endurance usage and thermal history strengthen concern about this SSD, but do not independently prove why its reliability bit is set.

At inspection, `zpool status -P` still reported `rpool` ONLINE with zero read/write/checksum errors and no known data errors. That and the empty NVMe error log do not exclude the recorded latency stalls or negate failed SMART health.

### Assessment and next steps for proxmox2-old

Migration writes appear to overwhelm an already worn, thermally stressed SSD. Because host services and the migration destination share this single-device root pool, storage stalls can block both the migration and ordinary host activity, making the host appear frozen. The evidence establishes severe stalls on the affected device; it does **not** prove whether wear, thermal throttling, firmware/controller behaviour, or another issue is the primary mechanism. This differs from the recorded **proxmox5 e1000e transmit-queue hang**; do not apply its NIC diagnosis or mitigation to this host without network evidence.

Verify recoverable backups and plan replacement of this SSD before another heavy migration. Inspect NVMe cooling, heatsink contact, and airflow. Replacement and cooling changes have **not** been performed as part of this investigation.

None of the five existing runs contains `nvme-health.log`, so individual latency spikes cannot be directly matched to contemporaneous SMART temperatures or controller error snapshots. If further collection is needed, ensure `nvme-cli` is available and use the current migration monitor to capture that file, alongside ZFS, process, and disk-latency evidence. Prefer preserving evidence and replacing the suspect drive over repeated stress tests on the only root-pool device.

## proxmox5 recurrence and follow-up, 2026-10-10

Capture: `/var/log/proxmox-migration-monitor/proxmox5-postmortem-20261010T083547Z`.
At October 9 23:40:43 CEST both Corosync links failed and e1000e began reporting hardware-unit hangs. There are 19,603 reports through October 10 10:34:07, with unchanged TDH 1, TDT 1c, next_to_use 1c and next_to_clean 0. NFS timeouts started at 23:44:29. Local logging continued for almost eleven hours, supporting a NIC transmit stall rather than a complete host freeze. Both boots used 7.0.14-23-pve. No actual panic, lockup, OOM or disk I/O error was found; post-reset rpool was ONLINE without reported errors. A migration trigger was not established.

The four existing NIC captures had no hardware hangs and zero sampled RX/TX/CRC errors or TX timeouts. TSO/GSO remained off in all settings samples after reapplication on October 1 through the final October 7 12:24 CEST capture. No collector covered the failed October 9 boot. TSO/GSO were on after the October 10 reboot; incident-time settings are unknown.

On October 10 TSO/GSO were disabled again and verified off. `/etc/network/interfaces` now has `post-up /usr/sbin/ethtool -K nic0 tso off gso off` in the nic0 stanza. A timestamped backup is alongside that file. No network reload or reboot was used to apply this change.

The collector now adds `network-events.log` (link/address/route/neighbour changes) and `network-state.log` (routing, neighbour counters, bridge state, queue statistics, TCP sockets, interrupt/softirq/softnet counters, PCI AER and runtime power state), approximately every twelve samples. The postmortem collector additionally records physical-interface identity, offloads, driver counters, EEE and pause settings; these are post-reset readings, not incident-time state.

`proxmox-nic-monitor.service` runs the collector on proxmox5 across reboots, with gateway 10.1.1.1 and NAS 10.0.0.20 probes. Each start creates a new private local capture directory. Check with `systemctl status proxmox-nic-monitor`; stop with `systemctl stop proxmox-nic-monitor`. Logs accumulate while enabled; monitor local free space and archive old captures. This service does not change NIC settings. The boot-time offload hook is independent of the collector.
