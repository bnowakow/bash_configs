# NAS Embedded-etcd Monitoring Handoff

## Purpose

Run the same event-driven collector on `nas` so a Raft or WAL-latency event can
be correlated with both etcd members. A problem on either node can delay Raft
heartbeats and cause slow reads, request timeouts, or a leader election.

## Current Findings on proxmox3

- Embedded etcd has recorded repeated `slow fdatasync` events over the last
  week, including delays of 19.74 s, 16.28 s, 13.27 s, and several 3-11 s
  events. The warning threshold is 1 s.
- Current node and API readiness are healthy, and current peer network latency
  to `nas` is low with no observed packet loss.
- The local etcd data directory is on the ZFS `rpool` backed by one NVMe.
  ZFS and SMART status are healthy, so intermittent storage contention or host
  scheduling remains a leading hypothesis.

## Files to Copy to NAS

Required to run the collector:

- `monitor-k3s-etcd-latency.sh`

Optional reference only:

- `nas-etcd-monitoring-handoff.md`

Do not copy `/var/log/k3s-etcd-monitor/`; each node should retain its own local
evidence bundles.

## NAS Setup

1. Copy `monitor-k3s-etcd-latency.sh` to a suitable administrative directory
   on NAS and make it executable.
2. Identify the pool that holds `/var/lib/rancher/k3s/server/db/etcd`:

```bash
findmnt -T /var/lib/rancher/k3s/server/db/etcd -o TARGET,SOURCE,FSTYPE
zpool list
```

3. Start the collector. Replace `POOL_NAME` with the pool found above:

```bash
mkdir -p /var/log/k3s-etcd-monitor
systemd-run --unit=k3s-etcd-latency-monitor \
  --property=Restart=always \
  --property=RestartSec=5s \
  /path/to/monitor-k3s-etcd-latency.sh \
  --peer 10.0.0.50 \
  --zpool POOL_NAME
```

4. Verify it is active:

```bash
systemctl status k3s-etcd-latency-monitor --no-pager
```

The service is transient and will not survive a reboot. It creates a
timestamped directory under `/var/log/k3s-etcd-monitor/` only when it sees a
serious etcd/Raft signal: slow WAL fsync, delayed ReadIndex, request deadline,
peer failure, or leader change. While idle, it records a filtered etcd metrics
sample every 15 seconds and retains the last 40 minutes in
`/var/log/k3s-etcd-monitor/etcd-metrics-history/`.

Each evidence bundle includes the triggering k3s journal line, the latest 200 k3s journal lines, kernel logs, process snapshot, `vmstat`, PSI pressure data, ZFS pool and ARC state, TCP/NIC counters, `iostat`, ZFS I/O sampling, and a short peer ping sample. It also includes `etcd-metrics-before.prom`, `etcd-metrics-after.prom`, and `etcd-metrics-delta.log`, which show the change in selected WAL, backend-commit, peer-RTT, and Raft counters across the event. Compare the NAS and proxmox3 bundles by timestamp after an event.

## Stop Command

```bash
systemctl stop k3s-etcd-latency-monitor
```
