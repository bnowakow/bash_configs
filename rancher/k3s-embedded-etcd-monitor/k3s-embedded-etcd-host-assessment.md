# K3s Embedded-etcd Host Assessment

Run this assessment directly on the K3s host with `sudo`. Produce a short report
with the command output and a conclusion: **suitable**, **suitable with caveats**,
or **not suitable** for embedded etcd.

## Scope and safety

- Read-only inspection is preferred.
- Do not stop or restart K3s.
- Do not modify `/var/lib/rancher/k3s`.
- Do not run fio against `/var/lib/rancher/k3s`, `/var/lib/rancher/k3s/server/db`,
  `/var/lib/rancher/k3s/server/db/etcd`, Longhorn, or any production filesystem.
- The fio test below writes only to a disposable temporary directory and removes
  that test file when finished.
- If a command is unavailable or blocked, report that fact instead of working
  around it destructively.

## Host and resource inspection

```bash
hostname -f
uname -a
lscpu
free -h
uptime
vmstat 1 5
swapon --show
lsblk -o NAME,MODEL,SIZE,TYPE,FSTYPE,MOUNTPOINTS
findmnt -T /var/lib/rancher/k3s -o TARGET,SOURCE,FSTYPE,OPTIONS
df -hT / /var/lib/rancher/k3s /var/lib/longhorn
```

Check whether the K3s datastore is on local SSD/NVMe, ZFS, a network filesystem,
or a virtual/network block device. Record any active storage contention.

If this is a Proxmox host, also report whether K3s is running directly on the
hypervisor or inside a VM/LXC container. Prefer running K3s in a dedicated VM or
node with predictable disk and CPU resources.

## K3s and datastore inspection

```bash
k3s --version
systemctl is-active k3s
systemctl status k3s --no-pager -n 40
systemctl cat k3s
ps -ef | grep '[k]3s server'
stat -f /var/lib/rancher/k3s
ls -ld /var/lib/rancher/k3s/server/db
ls -ld /var/lib/rancher/k3s/server/db/etcd
```

If K3s is running, collect recent datastore-related messages without changing
anything:

```bash
journalctl -u k3s --since '2 hours ago' --no-pager | \
  grep -Ei 'etcd|database|datastore|raftex|leader|quorum|slow|timeout|latency|corrupt'
```

If `etcdctl` is installed, inspect health using the K3s-managed certificates:

```bash
ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
  --cert=/var/lib/rancher/k3s/server/tls/etcd/client.crt \
  --key=/var/lib/rancher/k3s/server/tls/etcd/client.key
```

## Disposable synchronous-write benchmark

The important embedded-etcd metric is low-latency synchronous storage. K3s
resource profiling uses approximately **50 IOPS and less than 5 ms latency** as
a useful embedded-etcd reference point.

First check that fio is installed:

```bash
command -v fio
```

If it is installed, run this against a disposable directory on the same
filesystem as `/var/lib/rancher/k3s`, but never against the live datastore:

```bash
test_dir=$(mktemp -d /root/k3s-fio-test.XXXXXX)
cleanup() { rm -rf -- "$test_dir"; }
trap cleanup EXIT

fio --name=k3s-like \
  --directory="$test_dir" \
  --size=512M \
  --bs=4k \
  --rw=randrw \
  --rwmixread=70 \
  --iodepth=1 \
  --numjobs=1 \
  --direct=1 \
  --runtime=60 \
  --time_based \
  --group_reporting
```

After the 60-second smoke test, run a longer 10-minute pass with the same
settings to expose rarer latency spikes:

```bash
test_dir=$(mktemp -d /root/k3s-fio-test.XXXXXX)
cleanup() { rm -rf -- "$test_dir"; }
trap cleanup EXIT

fio --name=k3s-like-long \
  --directory="$test_dir" \
  --size=512M \
  --bs=4k \
  --rw=randrw \
  --rwmixread=70 \
  --iodepth=1 \
  --numjobs=1 \
  --direct=1 \
  --runtime=600 \
  --time_based \
  --group_reporting
```

Record read/write IOPS, average latency, 95th/99th percentile latency, and
maximum latency. Pay particular attention to latency spikes, not only average
throughput.

If fio is unavailable, do not install packages automatically. Report that the
write-latency benchmark could not be run.

## Network checks for HA embedded etcd

For every other K3s server, verify stable private-IP connectivity on TCP ports
6443, 2379, and 2380. Use the actual inventory hostnames/IPs:

```bash
nc -vz -w 3 SERVER_IP 6443
nc -vz -w 3 SERVER_IP 2379
nc -vz -w 3 SERVER_IP 2380
ping -c 20 SERVER_IP
```

Report packet loss, approximate latency, firewall failures, and whether traffic
uses a private LAN, Tailscale, or another overlay. Embedded etcd should use a
stable, low-latency private network between servers.

## Assessment guidance

Classify the host as likely suitable when:

- at least 2 dedicated CPU cores and 2 GiB RAM are available to K3s;
- storage is local SSD/NVMe;
- synchronous 4 KiB write latency is normally below 5 ms;
- there is no sustained I/O wait or CPU steal/contention;
- the filesystem has adequate free space;
- HA servers have reliable private connectivity.

Important architectural caveat: one K3s server is not HA, regardless of the
datastore. A proper embedded-etcd HA design uses three or more K3s servers and a
stable VIP/load balancer for the Kubernetes API. Two servers cannot tolerate the
loss of one member while retaining etcd quorum.

## Preliminary facts already observed

The host previously reported:

- Intel Core i7-9700, 8 physical cores;
- 32 GiB RAM, approximately 16 GiB available at inspection time;
- an Apacer 512 GB NVMe device backing ZFS;
- K3s `v1.36.4+k3s1`;
- no swap;
- low observed I/O wait during a brief sample;
- only one active K3s server in the repository inventory.

These facts suggest adequate compute capacity, but they do not establish
embedded-etcd suitability until synchronous-write latency and actual HA network
conditions are measured.

## Observed benchmark results

### proxmox3, 2026-09-10

Host facts at benchmark time:

- Hostname `proxmox3.alpaca-orfe.ts.net`;
- Proxmox kernel `7.0.14-16-pve`;
- K3s `v1.36.4+k3s1`, active as a single `control-plane,etcd` node;
- Intel Core i7-9700, 8 physical cores;
- 31 GiB RAM, approximately 16 GiB available;
- no swap;
- `/var/lib/rancher/k3s` on ZFS `rpool/ROOT/pve-1`;
- ZFS pool backed by an Apacer AS2280P4 512 GB NVMe device;
- root/K3s filesystem 456 GB total, 365 GB free, 21% used;
- `/var/lib/longhorn` mounted separately on `/dev/zd0` ext4.

60-second fio pass:

- read: 26.3k IOPS, 103 MiB/s, average latency 25.6 us, p95 6.3 us,
  p99 528 us, max 62.7 ms;
- write: 11.3k IOPS, 44.0 MiB/s, average latency 28.0 us, p95 19 us,
  p99 529 us, p99.9 3.36 ms, p99.95 6.0 ms, p99.99 10.2 ms, max 25.3 ms.

10-minute fio pass:

- read: 1363 IOPS, 5456 KiB/s, average latency 511 us, p95 2.02 ms,
  p99 6.46 ms, p99.5 8.72 ms, p99.9 11.2 ms, p99.95 12.1 ms,
  p99.99 16.6 ms, max 64.9 ms;
- write: 584 IOPS, 2339 KiB/s, average latency 513 us, p95 2.02 ms,
  p99 6.52 ms, p99.5 8.72 ms, p99.9 11.2 ms, p99.95 12.4 ms,
  p99.99 15.9 ms, max 33.8 ms.

Assessment: **suitable with caveats**. The 60-second result is very strong, and
the 10-minute result remains far above the 50 IOPS reference. However, the
longer run shows recurring tail latency above 5 ms from p99 onward and rare
spikes up to tens of milliseconds. This is probably acceptable for a small
single-node or lightly loaded K3s control plane, but the host is still a
Proxmox hypervisor with ZFS and Longhorn activity, so storage contention should
be watched. This single server is not HA regardless of datastore performance.


### nas, 2026-09-11 (potential K3s host)

Host facts at benchmark time:

- Hostname `nas.localdomain`; TrueNAS kernel
  `6.12.105-production+truenas`;
- AMD Ryzen 5 PRO 4655G, 6 physical cores / 12 logical CPUs;
- 125 GiB RAM, approximately 46 GiB available; no swap;
- `/root` on ZFS `boot-pool/ROOT/25.10.7/root`;
- `boot-pool` is a healthy ZFS mirror of local SATA SSD partitions `sdj3`
  (SSDPR-CX400-256-G2) and `sdl3` (Samsung SSD 750 EVO 250GB), with no known
  data errors;
- 232 GiB pool size, 225 GiB free, 3% used;
- K3s is not currently installed, so datastore and HA network checks were not
  applicable.

The fio test used a disposable 512 MiB file in `/root/k3s-fio-test.*` on
`boot-pool`; each directory was removed automatically and cleanup was verified.

60-second fio pass:

- read: 50.0k IOPS, 195 MiB/s, average latency 12.6 us, p95 14 us,
  p99 30 us, p99.9 1.11 ms, max 89.9 ms;
- write: 21.4k IOPS, 83.8 MiB/s, average latency 15.8 us, p95 26 us,
  p99 55 us, p99.9 1.02 ms, p99.99 3.20 ms, max 121 ms.

10-minute fio pass:

- read: 52.6k IOPS, 205 MiB/s, average latency 7.81 us, p95 18 us,
  p99 20 us, p99.9 180 us, p99.99 627 us, max 262 ms;
- write: 22.5k IOPS, 88.0 MiB/s, average latency 24.8 us, p95 157 us,
  p99 202 us, p99.9 243 us, p99.99 302 us, max 259 ms.

Assessment: **suitable with caveats**. The sustained synchronous 4 KiB write
latency is far below the 5 ms reference and write IOPS are far above the 50
IOPS reference. Rare 121--259 ms latency spikes occurred in both passes, and a
post-test `vmstat` sample showed 8--9% I/O wait while the NAS was active; watch
storage contention if this host also serves NAS workloads. Validate K3s
resource isolation and private HA networking before using this host in an
embedded-etcd cluster.


### proxmox2-old, 2026-09-11 (potential K3s host)

Host facts at benchmark time:

- Hostname `proxmox2-old.localdomain`; Proxmox kernel `7.0.14-16-pve`;
- AMD Ryzen 5 PRO 2400GE: 4 physical cores / 8 logical CPUs; 30 GiB RAM, approximately 9.4 GiB available; no swap;
- this is the bare-metal Proxmox hypervisor, not a dedicated K3s VM or LXC;
- the intended default datastore path is on ZFS `rpool/ROOT/pve-1`, backed by a local Patriot M.2 P300 256GB NVMe device;
- `rpool` was healthy, with 90.7 GiB available to the root dataset; its single NVMe vdev was 58% allocated and 69% fragmented;
- ZFS uses `sync=standard` and `logbias=latency` for the root dataset;
- pre-test `vmstat` showed 0% I/O wait and 0% CPU steal; post-test sampling showed 0--1% I/O wait;
- the same ZFS pool serves three running VMs: Home Assistant (8 GiB), transmission (3 GiB), and Proxmox Backup Server (4 GiB);
- K3s is not installed, so datastore health and HA network checks were not applicable.

`fio` 3.39 was installed explicitly to run this assessment. Both tests used a disposable 512 MiB file in `/root/k3s-fio-test.*` on `rpool/ROOT/pve-1`; each test directory was removed automatically and cleanup was verified.

60-second fio pass:

- read: 26.7k IOPS, 104 MiB/s, average latency 24.54 us, p95 15 us, p99 338 us, p99.9 2.80 ms, p99.99 7.31 ms, max 123 ms;
- write: 11.5k IOPS, 44.8 MiB/s, average latency 28.37 us, p95 25 us, p99 347 us, p99.9 2.80 ms, p99.99 7.18 ms, max 50.3 ms.

10-minute fio pass:

- read: 17.5k IOPS, 68.6 MiB/s, average latency 37.91 us, p95 10 us, p99 408 us, p99.9 5.54 ms, p99.99 34.3 ms, max 176 ms;
- write: 7,519 IOPS, 29.4 MiB/s, average latency 42.94 us, p95 19 us, p99 416 us, p99.9 5.54 ms, p99.95 7.18 ms, p99.99 35.4 ms, max 234 ms.

Assessment: **suitable with caveats**. The sustained synchronous 4 KiB write latency is far below the 5 ms reference through p99, and write IOPS are far above the 50 IOPS reference. The 10-minute pass exposed rare latency spikes, with p99.9 slightly above 5 ms and a 234 ms maximum. This host is also a shared Proxmox hypervisor whose root ZFS pool serves active VMs, so I/O or CPU contention may affect etcd. Prefer a dedicated K3s VM with reserved CPU/RAM and storage, or a dedicated node. A single K3s server would still not provide HA.

## Cross-host summary

All three candidate hosts exceed the K3s embedded-etcd reference of roughly
50 IOPS and less than 5 ms storage latency under normal operation. The main risk
is not throughput; it is tail latency during shared-storage contention.

| Host | 60s read IOPS | 60s write IOPS | 10m read IOPS | 10m write IOPS | Summary |
| --- | ---: | ---: | ---: | ---: | --- |
| `nas` | 50.0k | 21.4k | 52.6k | 22.5k | Best storage candidate; excellent 10-minute p99.99 write latency, but watch NAS workload contention. |
| `proxmox2-old` | 26.7k | 11.5k | 17.5k | 7,519 | Good candidate; shared Proxmox/ZFS pool and fragmentation are the main caveats. |
| `proxmox3` | 26.3k | 11.3k | 1,363 | 584 | Usable but weakest storage candidate; 10-minute p99+ tail latency is noticeably higher. |

Preferred order for embedded-etcd storage suitability:

1. `nas`
2. `proxmox2-old`
3. `proxmox3`

The most important comparison is the 10-minute write IOPS and write tail
latency. `nas` is the strongest result by both throughput and latency. It kept
10-minute write p99.99 latency around 302 us while sustaining 22.5k write IOPS.
`proxmox2-old` is still strong, with 7,519 write IOPS and p99 write latency
around 416 us, but rare spikes reached 234 ms and the root ZFS pool is shared
with active VMs. `proxmox3` remains far above the minimum IOPS reference, but
its 10-minute write p99 was 6.52 ms and p99.9 was 11.2 ms, making it the least
comfortable member from a storage-tail-latency perspective.

For a three-server embedded-etcd K3s cluster, this set of hosts is plausible if
all etcd peer traffic uses a stable, low-latency private network. Before relying
on HA, verify TCP connectivity and packet loss between every server on ports
6443, 2379, and 2380. Avoid using unstable overlays or high-latency paths for
etcd peer traffic. Also avoid colocating unusually heavy NAS, backup, VM, or
Longhorn activity on the same disks used by etcd where possible.
