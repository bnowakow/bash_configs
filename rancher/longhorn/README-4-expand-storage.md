# Expand Longhorn host storage to 150GiB per host

Prepared 2026-10-25 after BookStack migration. **Proxmox3 expansion to 150GiB
completed 2026-10-25 18:14:34 UTC / 19:14:34 CET** on explicit user instruction
(100 → 128GiB first, then 128 → 150GiB for additional buffer).
**Proxmox2-old expansion from 80 to 150GiB completed 2026-10-25 18:35:36 UTC /
19:35:36 CET**, with Longhorn reconciliation verified at 18:36:10 UTC.
Both hosts are now at the selected backing size. Reservations, PVC sizes and
migration caps are unchanged. See the maintenance logs for
[proxmox3](proxmox3-expansion-2026-10-25.log) and
[proxmox2-old](proxmox2-old-expansion-2026-10-25.log).

## Proxmox2-old completed expansion and outstanding health checks

The [2026-10-25 I/O incident log](io-pressure-incident-2026-10-25.md) records
repeated API/k3s failures, severe storage stalls, runtime workload stops, and a
confirmed **NVMe temperature alarm and active thermal management on proxmox2-old**.
Additional cooling cleared the temperature warning, but SMART still reported
degraded NVM reliability (`0x04`) and failed health. The user explicitly requested
the local 150GiB expansion after reviewing that finding; it is now complete.
Preflight passed a ten-minute screen of both direct APIs, both hosts' I/O PSI
and unchanged k3s restart counts (0 / 60). Local SMART temperature was 41 C,
thermal-management counters stayed unchanged, and the reliability warning was
recorded in the maintenance decision. All 39 production volumes had completed
NAS backup records; migration restore evidence was reviewed, without claiming
a fresh restore of every current backup. Expansion does not repair the drive
or replace its replacement plan.
Proxmox3's own NVMe passed SMART (warning `0x00`, 54 C), its pool was
healthy, both APIs were ready and I/O pressure was low before its authorized
local-only resize. Read the incident log before further maintenance.

At final post-verification (approximately 18:15 UTC), Longhorn reported proxmox3
maximum **147.09GiB**, physical free **122.56GiB**, scheduled **47.27GiB**,
reserved **0**, and nominal remaining **99.82GiB**. Disk key `default-disk`, disk UUID, mount
path and filesystem UUID were preserved. All attached volumes were healthy;
running engines had two RW replicas. Five detached production volumes had only
one nonfailed local replica before the resize (Homer, Homer-without-auth, Radarr
config, Bazarr config and OpenBooks books); completed NAS backups were present.
Those exceptions were recorded, not repaired by the resize. The user later
requested application restoration; by 20:14 UTC all restored controllers were
ready and the five production exceptions had recovered through normal
reattachment. See the [incident log](io-pressure-incident-2026-10-25.md).
Capacity growth itself was not incident repair.

## Selected target sizes

The user selected **150GiB backing zvols per host** for future buffer.
Both expansions are complete. Proxmox2-old grew directly from 80GiB to
**150GiB = 161061273600 bytes**, without an intermediate 128GiB step.
The commands below are retained procedure, not instructions to repeat the grow.
Preserve the two-replica policy; record and recover existing failed/missing
replicas rather than assuming the configured count proves two good copies.

| Host | Current backing device | Current Longhorn filesystem maximum | Recommended backing zvol | Approximate increase |
| --- | ---: | ---: | ---: | ---: |
| proxmox2-old | 150GiB, expanded and verified | 147.09GiB | **150GiB — complete** | **+70GiB completed** |
| proxmox3 | 150GiB, expanded and verified | 147.09GiB | **150GiB — complete, user-selected buffer** | **+50GiB completed** |

These are **per-host sizes**, not a shared 150GiB pool. Both hosts need capacity
for a full replica set. With two storage nodes/two replicas, extra capacity on
only one host does not remove the smaller host's limit.

The current layout is a dedicated zvol with ext4 directly on the whole device:

```text
ZFS pool -> dedicated zvol -> ext4 -> /var/lib/longhorn -> Longhorn replica files
```

The local host exposes `/dev/zvol/rpool/longhorn` as `/dev/zd0`, now a 150GiB device.
Device numbers vary; discover the peer's actual dataset/device before modifying
it. Repository configuration also allows `/dev/zvol/MargokPool/longhorn`.
Do not assume both hosts use rpool or the same `/dev/zdN` number.

## Capacity calculation

Historical Longhorn snapshot before host expansion, after BookStack
(2026-10-25 ~13:40 UTC):

| Host | Maximum GiB | Physically free GiB | Longhorn reservation GiB | Scheduled GiB | Nominal remaining GiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| proxmox2-old | 78.19 | 55.08 | 7.82 | 47.26 | 23.11 |
| proxmox3 | 97.87 | 72.56 | 0 | 47.27 | 50.60 |

These are historical measurements. Use the
[current storage summary](current-app-storage-summary-2026-10-24.md) for the
post-expansion figures and re-measure both hosts immediately before maintenance.

- Completed production requests after Docker Mailserver cutover: **66.75GiB per
  host** with two replicas overall.
- Remaining target: Mailpile **9.25GiB**.
- Mailpile's unverified staging already reserves **9.25GiB per host**. Reuse it
  only after a successful fresh copy/verification; do not count it twice.
- Additional nominal allocation to finish, if Mailpile staging is reused:
  **0GiB**; otherwise **9.25GiB per host**. Mailpile's current staging remains
  unverified, so do not count it as migrated data.
- After all migrations: **76GiB production requests per host**, plus approximately
  0.01/0.02GiB of older tests: **76.01/76.02GiB scheduled**. Creating another
  Mailpile staging pair temporarily adds 9.25GiB per host until old staging is
  deliberately removed; this is not included in the steady-state total.

Raw zvol size is not identical to Longhorn `storageMaximum`. The completed
150GiB grows exposed **147.09GiB on each host** (exact bytes differ slightly
because of filesystem metadata geometry).

| Backing zvol per host | Estimated filesystem maximum | Nominal room after all migrations, current fixed reservations (node2 / node3) | Room if reserving 10% on both hosts instead |
| --- | ---: | ---: | ---: |
| **150GiB selected** | **~147.09GiB** | **~63.3 / 71.1GiB** | **~56.4GiB each** |

Longhorn reservations are byte amounts on existing disks: enlarging the zvol
must not be assumed to recalculate them as 10%. The procedure below preserves
existing values. Standardizing reservations is a **separate policy decision**.
The 10% column is an optional scenario, not part of the resize instructions.

150GiB gives substantial nominal growth room. The following is the historical
pre-Mailserver physical planning example; remeasure after cutover. It assumed
largest-host used space (~25.31GiB) + all then-remaining target sizes (38GiB) + **10GiB actual data growth
+ 10GiB additional local snapshot/churn** = ~83.31GiB. On a ~147.09GiB filesystem,
that leaves ~63.78GiB free (~43%). This is a scenario, not a growth forecast:
re-measure mail, snapshot use and staging contents before execution.

Requested capacity, actual replica/snapshot bytes and filesystem free space
must all be tracked. If every requested production GiB eventually fills,
76GiB + 10GiB growth + 10GiB snapshots = 96GiB, leaving ~51.09GiB (~35%) free.
A stricter example is 76GiB fully used + 25% data growth (19GiB) + 15GiB local
snapshots = 110GiB, leaving ~37.09GiB (~25%) free. These figures describe the
Longhorn filesystem, **not guaranteed physical capacity in its backing pool**.
They do not include unlimited snapshot retention or a full duplicate of every
volume for simultaneous restore tests. Run small restore tests sequentially.

## Admission policy and underlying pool capacity

The old **55GiB production migration cap** cannot cover the completed 76GiB
plan. Propose a reviewed **100GiB production-request cap per host** after resize;
that permits the migration and 24GiB of additional requested growth. Admit a
change only if both hosts also pass nominal scheduling and physical-space gates.
That cap alone does not guarantee space for snapshots or fully used volumes.
It remains a proposal; this document does not lift the current 55GiB cap.

A sparse zvol's size is virtual capacity, not guaranteed backing-pool space.
Before growing to 150GiB, inspect each pool, competing VMs/datasets, quotas,
reservations and retained ZFS snapshots. Plan for the same worst-case data and
churn on both pools; keep an additional pool-level operating margin (use 20% as
a planning floor, more if write latency warrants it). Do not count compression
or sparse allocation as guaranteed capacity. Both grows are complete; the
proxmox2-old physical limit below remains a separate admission constraint.

**Latest physical capacity after VM moves (approximately 19:05 UTC):** user-initiated
migrations of VM 700 (Proxmox Backup Server) and VM 601 (Transmission) to proxmox5
both returned TASK OK; their attached source disks were released. The local
236.00GiB pool now has **151.21GiB allocated / 84.79GiB physically free**, leaving
**37.59GiB additional physical allocation above the 20% pool-free floor**.
This shared headroom must cover data, snapshots, metadata and other pool growth;
it is not an additional application-payload quota. Both VMs remain stopped.
No further Longhorn resize was performed or needed. Details and I/O observations:
[migration record](io-pressure-incident-2026-10-25.md#vm-migrations-released-physical-space--2026-10-25-approximately-2005-cet--1905-utc).
The drive reliability warning and separate migration admission checks remain.

**Historical physical limit immediately after expansion (18:36:10 UTC):** the NVMe-backed
pool is **236.00GiB**, with **185.04GiB allocated / 50.96GiB physically free**.
ZFS reports about **43.66GiB available to datasets**, after its internal space
accounting. A 20% pool margin is **47.20GiB**, leaving only **3.76GiB additional
physical allocation above that planning floor**. Approximate dataset allocation:
root **76.33GiB**, VM zvols **84.79GiB**, Longhorn zvol **23.90GiB**; retained
ZFS snapshot usage and explicit dataset reservations were zero at preflight.
These dataset accounting figures need not sum exactly to pool allocation.

The sparse 80 → 150GiB resize did not reserve the added 70GiB or create physical
space. Longhorn now reports **125.68GiB filesystem free**, which cannot all be
filled from this pool. Do not admit new migrations using that number alone;
the physical margin, drive reliability warning and migration cap still apply.
Plan greater physical capacity with the replacement drive and re-measure before
future growth. No automatic cleanup or deletion was performed.

## Live post-expansion capacity and Mailserver copy — 2026-10-26 16:52 CET

Both 150GiB Longhorn filesystems are Ready and schedulable. Four Mailserver
RWO claims totaling 28.75GiB per host are Bound. The warm copy and final
stopped-writer sync completed; target actual sizes total about 23.45GiB.
Mailserver cutover completed 2026-10-26 17:16 CET. The app is Ready 1/1 using
the Longhorn PVCs, and all four volumes report healthy with two replicas. The
four original local-path PVCs, data directories and released PV objects were
removed on user instruction by 17:34 CET, reclaiming about 20GiB of apparent
local data. The current root pool reports 155GiB allocated / 317GiB free. Full details are in the
[Mailserver handoff](migrations/docker-mailserver-2026-10-26/HANDOFF.md).

| Host | Longhorn max | Available | Scheduled | Reserved | Pool size | Pool allocated | Pool free | Headroom above 20% free floor |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| proxmox2-old | 147.09GiB | 99.45GiB | 76.03GiB | 7.82GiB | 236GiB | 167.51GiB | 68.49GiB | **21.29GiB** |
| proxmox3 | 147.09GiB | 97.15GiB | 76.04GiB | 0GiB | 472GiB | 174.32GiB | 297.68GiB | **203.28GiB** |

At the 16:52 CET capacity snapshot, nominal room after Longhorn scheduling and reservation was 63.24GiB on
proxmox2-old and 71.05GiB on proxmox3. This is not the same as physical pool
headroom. The peer SSD reliability warning remains. A full second two-replica
restore of the 23.45GiB target would exceed proxmox2-old's physical headroom
above the 20% floor. For restore validation, use a one-replica scratch restore
pinned to proxmox3 or add physical capacity; retain two replicas on production
volumes. Both Kubernetes APIs remained ready, etcd voters healthy, and restart
counts unchanged (60 local / 0 peer) during copy and source restoration. I/O
pressure returned to low readings after brief copy-related peaks.

| Host | Longhorn maximum | Scheduled | Reserved | Longhorn reported available | ZFS pool total / allocated / free | Physical headroom above 20% pool-free floor |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| proxmox2-old | 147.09GiB | 76.03GiB | 7.82GiB | 99.45GiB | 236 / 167.51 / 68.49GiB | **21.29GiB** |
| proxmox3 | 147.09GiB | 76.04GiB | 0 | 97.15GiB | 472 / 174.32 / 297.68GiB | **203.28GiB** |

Longhorn's reported-available values were collected around 16:50 CET. Host `df`
reported about 92.6GiB free on the peer and 90.2GiB locally; ZFS physical
allocation is the stricter peer constraint. Pool headroom subtracts a 20% free
space floor (47.20GiB peer / 94.40GiB local) from current ZFS physical free
space. The target volumes report about **23.45GiB total actual data**; the
peer's remaining 21.29GiB headroom above the floor is too small for a second
full two-replica restore copy at once. Use a one-replica proxmox3-only isolated
restore test or add backing capacity before that gate; keep the production
two-replica policy unchanged. The proxmox2-old NVMe still has a degraded
reliability warning.

The 55GiB administrative production migration cap has not been changed. The
The user's 2026-10-26 instruction explicitly authorized the Mailserver
migration as a task-specific exception; its cutover is complete and production
requests are now 66.75GiB (38GiB existing + 28.75GiB Mailserver), above the
previous cap. The general cap remains unchanged. See the
[Mailserver handoff](migrations/docker-mailserver-2026-10-26/HANDOFF.md).

### ZFS pool space versus ext4 free space

Historical read-only measurement on 2026-10-25, after the grow **and before the
VM 700/601 migrations**. The latest pool capacity is recorded above. Small differences
from the 18:36:10 UTC snapshot above reflect ongoing allocation and sampling.
There is one ZFS pool on this NVMe, `rpool`, and it reports ONLINE.

| Layer / measurement | GiB | Meaning |
| --- | ---: | --- |
| ZFS pool total | 236.00 | Pool capacity on the NVMe |
| ZFS pool allocated | 185.03 | Physical pool allocation across all datasets/zvols |
| ZFS pool free | 50.97 | Physical space not yet allocated |
| ZFS dataset available | 43.67 | Shared allocation budget after ZFS internal space accounting |
| Longhorn backing zvol | 150.00 | Sparse virtual device size |
| Longhorn ext4 total | 147.09 | Filesystem capacity after metadata overhead |
| Longhorn ext4 used | 21.33 | Filesystem blocks used |
| Longhorn ext4 free | 125.76 | Free blocks, including reserved free space (`f_bfree`) |
| Longhorn ext4 available | 118.93 | Available blocks reported by `df` (`f_bavail`) |
| Ext4 reserved free difference | 6.84 | `f_bfree - f_bavail`; included in free, excluded from available |
| Pool free above the 20% planning floor | 3.77 | Further physical allocation before reaching 47.20GiB free |

The **43.67GiB ZFS dataset-available figure is shared**, not a separate allowance
for the root dataset, each VM and Longhorn. `/` is ZFS; only the dedicated
Longhorn zvol in this layout contains ext4. Layout:
`NVMe → rpool → sparse rpool/longhorn zvol → ext4 → /var/lib/longhorn`.

Ext4 sees its enlarged virtual block device and cannot account for competing
allocations in the underlying ZFS pool. Its 118.93GiB available figure therefore
does not promise that much physical backing. Neither filesystem free space nor
Longhorn nominal scheduling room overrides the shared pool limit. Ext4's
reserved-free difference is also distinct from Longhorn's unchanged 7.82GiB
`storageReserved` scheduling reservation. No reservations were changed.

Increasing volsize does **not** repair the observed ZFS/etcd I/O stalls. Require
healthy APIs, stable k3s restart counts and low sustained I/O pressure before
maintenance. Perform one host at a time; this is a two-voter etcd cluster, so
do not restart both hosts/services together. No full cluster drain is needed
for an online ext4 grow, and draining a two-node storage cluster can provoke
unnecessary rebuilds and attachment moves.

## 1. Inventory and record the exact targets

Run on **each real host**, using sudo. A Codex sandbox may show a read-only bind
of the host mount: that does not establish that the host ext4 filesystem is
read-only. Check from the actual host namespace. If it really is read-only or
has filesystem errors, investigate first; do not force it writable.

```bash
hostname
sudo findmnt -T /var/lib/longhorn -o TARGET,SOURCE,FSTYPE,OPTIONS
sudo df -hT /var/lib/longhorn
sudo lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINTS
sudo blkid -t LABEL=longhorn
sudo zfs list -p -t volume -o name,volsize,used,available,refreservation
sudo zpool list -p -o name,size,alloc,free,capacity,health
sudo zpool status
sudo smartctl -x /dev/nvme0n1  # Verify the actual pool device/model first.
cat /proc/pressure/io
sudo systemctl show k3s -p ActiveState -p SubState -p NRestarts
sudo zfs get -r quota,refquota,reservation,refreservation <confirmed-pool>
```

Replace `<confirmed-pool>`; do not paste the placeholder literally. Confirm
which zvol resolves to the device mounted at `/var/lib/longhorn`, using
`readlink -f /dev/zvol/<pool>/<volume>`. Confirm ext4 is directly on that device
with **no partition table, LVM or encryption layer** before following step 3.
The procedure differs for those layers or for a disk passed into a VM.

Record existing filesystem UUID, zvol byte size, filesystem size, Longhorn disk
key/path and `storageReserved`. Obtain current verified application backups and
confirm healthy replicas on both hosts. A whole-zvol snapshot of a busy Longhorn
disk is not a substitute for verified application/native Longhorn backups.

```bash
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get --raw=/readyz
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml --server=https://10.0.0.50:6443 get --raw=/readyz
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml --server=https://10.0.0.72:6443 get --raw=/readyz
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n longhorn-system get nodes.longhorn.io -o yaml
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n longhorn-system get volumes.longhorn.io
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n longhorn-system get replicas.longhorn.io
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n longhorn-system get settings.longhorn.io storage-minimal-available-percentage storage-over-provisioning-percentage
```

Use the live settings. Planning above assumes no overprovisioning (100%).
The nominal budget is `maximum - reserved - scheduled`; Longhorn's separate
physical-availability threshold can still reject scheduling. Do not increase
overprovisioning or reduce replica count to make the plan appear to fit.

## 2. Record major actions

Use a durable, timestamped maintenance log on each host; keep diagnostic output
private and do not include tokens/Secret contents. For example, in Bash:

```bash
resize_log="$HOME/longhorn-resize-$(date -u +%Y%m%dT%H%M%SZ).log"
log_resize() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$resize_log"; }
log_resize "START host=$(hostname): inventory and backups verified; resizing confirmed Longhorn zvol"
```

Record chosen dataset/device, before/after sizes, commands/results, health
checks and any failure. Save the final Longhorn snapshot in this repository's
capacity documentation after verification.

## 3. Grow the confirmed zvol, then ext4

The following is a **template for one host**, not an auto-discovery script.
Set `longhorn_dataset` to the verified dataset from step 1. `rpool/longhorn`
was observed on both hosts, but verify the peer's mount/device mapping again.
The selected target is **150G / 150GiB**, not 150 decimal GB.
OpenZFS size suffixes here are binary units (GiB).

```bash
# Set these only after matching the mount, zvol and underlying device.
set -euo pipefail
longhorn_expected_host='proxmox2-old'
if [ "$(hostname -s)" != "$longhorn_expected_host" ]; then
  log_resize "STOP: expected $longhorn_expected_host; refusing to resize another host"
  exit 1
fi
longhorn_dataset='rpool/longhorn'  # EXAMPLE: peer may use a different pool
longhorn_device="/dev/zvol/$longhorn_dataset"
longhorn_target_bytes=$((150 * 1024 * 1024 * 1024))  # 161061273600
longhorn_current_bytes=$(sudo zfs get -Hp -o value volsize "$longhorn_dataset")
longhorn_uuid_before=$(sudo blkid -s UUID -o value "$longhorn_device")
longhorn_reservation_before=$(sudo zfs get -Hp -o value refreservation "$longhorn_dataset")
if [ "$(findmnt -n -T /var/lib/longhorn -o TARGET)" != /var/lib/longhorn ] ||
   [ "$(findmnt -n -T /var/lib/longhorn -o SOURCE)" != "$(readlink -f "$longhorn_device")" ] ||
   [ "$(findmnt -n -T /var/lib/longhorn -o FSTYPE)" != ext4 ]; then
  log_resize 'STOP: mount does not match the confirmed whole-device ext4 zvol'
  exit 1
fi
case ",$(findmnt -n -T /var/lib/longhorn -o OPTIONS)," in
  *,rw,*) ;;
  *) log_resize 'STOP: host filesystem is not writable'; exit 1 ;;
esac
log_resize "IDENTITY dataset=$longhorn_dataset device=$longhorn_device UUID=$longhorn_uuid_before refreservation=$longhorn_reservation_before"

# Refuse shrink or a no-op; inspect rather than forcing another command.
if [ "$longhorn_current_bytes" -ge "$longhorn_target_bytes" ]; then
  log_resize 'STOP: current zvol is already at or above the requested target'
else
  log_resize "GROW START $longhorn_dataset: $longhorn_current_bytes -> $longhorn_target_bytes bytes"
  if sudo zfs set "volsize=$longhorn_target_bytes" "$longhorn_dataset"; then
    sudo udevadm settle --timeout=30
    longhorn_visible_bytes=$(sudo blockdev --getsize64 "$longhorn_device")
    if [ "$longhorn_visible_bytes" -eq "$longhorn_target_bytes" ]; then
      log_resize 'ZVOL GROW VERIFIED; starting ext4 online grow'
      if sudo resize2fs "$longhorn_device"; then
        test "$(sudo blkid -s UUID -o value "$longhorn_device")" = "$longhorn_uuid_before"
        test "$(sudo zfs get -Hp -o value refreservation "$longhorn_dataset")" = "$longhorn_reservation_before"
        log_resize 'EXT4 GROW COMPLETE; verify mount and Longhorn capacity next'
      else
        log_resize 'STOP: ext4 grow failed; retain enlarged zvol and investigate'
      fi
    else
      log_resize 'STOP: device size has not updated; do not force ext4 resize'
    fi
  else
    log_resize 'STOP: zvol grow failed; do not run resize2fs'
  fi
fi
```

Do not repeat the resize on either host: both are already at 150GiB. Do not run
`mkfs`, `zfs create`, `zfs destroy`, shrink volsize, change volblocksize, reduce
ext4 reserved blocks or recreate the disk. Do not run `e2fsck` on a mounted
filesystem. This whole-device layout requires no `growpart` or `parted`.
If zvol growth succeeded but filesystem growth did not, fix the problem and
retry **only the filesystem grow after confirming the enlarged device**; do
not shrink the zvol back. The UUID and mount path should remain unchanged.

## 4. Verify one host before touching the other

```bash
sudo blockdev --getsize64 "$longhorn_device"
sudo zfs get volsize,used,available,refreservation "$longhorn_dataset"
sudo findmnt -T /var/lib/longhorn -o TARGET,SOURCE,FSTYPE,OPTIONS
sudo df -hT /var/lib/longhorn
sudo blkid "$longhorn_device"
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n longhorn-system get nodes.longhorn.io -o yaml
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n longhorn-system get volumes.longhorn.io
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get --raw=/readyz
log_resize 'HOST VERIFICATION: record measured filesystem/Longhorn sizes and replica/API health'
```

Longhorn should detect the enlarged filesystem on its existing disk: check
`status.diskStatus.<disk-key>.storageMaximum` and `storageAvailable`, disk
Ready/Schedulable and unchanged disk UUID/path. Let reconciliation finish;
no PVC recreation or Longhorn reinstall is expected. If it does not update,
inspect manager logs and host filesystem visibility before restarting anything.
Do not delete/re-add the Longhorn disk as a refresh mechanism.

Verify volume health, expected two-host replicas, representative applications
and current backups. Recheck API readiness and I/O pressure over time. Only then
repeat inventory, logging, grow and verification on the other host. Record final
measured per-host budgets and review the proposed cap before planning Mailpile.
The original Mailserver local-path PVCs have been deleted; their Released PVs
still retain old data. Do not clear those PVs/data without a separate cleanup
decision.

## Host expansion vs application PVC expansion

Host expansion provides space for more replicas; it does **not** enlarge app
PVC requests or their mounted filesystems. To grow an existing app claim later,
confirm its StorageClass has `allowVolumeExpansion: true`, increase its request
in the owning **Fleet storage bundle**, apply that changed bundle through the
existing Fleet-native workflow, and verify PVC capacity, resize conditions,
actual pod filesystem and Longhorn volume/replica health. Do not shrink claims
or bypass the external-claim ownership used by the migration bundles.

## References

- [Longhorn 1.13 disk scheduling and reservations](https://longhorn.io/docs/1.13.0/nodes-and-volumes/nodes/multidisk/)
- [Longhorn 1.13 scheduling settings](https://longhorn.io/docs/1.13.0/references/settings/)
- [Longhorn space consumption and snapshots](https://longhorn.io/kb/space-consumption-guideline/)
- [OpenZFS zvol sizing](https://openzfs.github.io/openzfs-docs/Basic%20Concepts/Datasets/ZVOLs.html)
- [OpenZFS native properties](https://openzfs.github.io/openzfs-docs/man/master/7/zfsprops.7.html)
- [resize2fs online ext4 growth](https://man7.org/linux/man-pages/man8/resize2fs.8.html)

Related: [current capacity](current-app-storage-summary-2026-10-24.md),
[remaining migrations](remaining-migration-priority-2026-10-24.md),
[existing host setup](README-1-longhorn-on-second-node.md).
The user confirmed a CloudCasa backup exists for the source local-path claims;
its restore contents were not independently inspected here. The source PVCs,
local directories and PV objects have been removed. A further 28 migrated
local-path sources on proxmox3 were reclaimed on 2026-10-26; its `rpool` now
reports 146GiB allocated / 326GiB free. All 39 migrated local-path sources
have now been reclaimed, including the 11 on proxmox2-old. Mailpile's two
active local-path claims remain because Mailpile has not been migrated. See the
[reclamation log](local-path-reclamation-2026-10-26.md). The storage-headroom
table above is a pre-cutover snapshot and should be remeasured before another
migration.
