# Expand Longhorn host storage to 150GiB per host

Prepared 2026-10-25 after BookStack migration. **Proxmox3 expansion to 150GiB
completed 2026-10-25 18:14:34 UTC / 19:14:34 CET** on explicit user instruction
(100 → 128GiB first, then 128 → 150GiB for additional buffer).
The peer was not resized; reservations, PVC sizes and migration caps are unchanged.
See the [maintenance log](proxmox3-expansion-2026-10-25.log).

## Proxmox2-old handoff and outstanding health checks

The [2026-10-25 I/O incident log](io-pressure-incident-2026-10-25.md) records
repeated API/k3s failures, severe storage stalls, runtime workload stops, and a
confirmed **NVMe temperature alarm and active thermal management on proxmox2-old**.
Additional cooling cleared the temperature warning, but SMART still reported
degraded NVM reliability (`0x04`) and failed health. **The next requested target
is 150GiB on proxmox2-old**, using the procedure below on that host. This edit
does not claim the drive warning is resolved or that the peer was resized.
Repeat SMART, API, latency, temperature, replica and backup checks there before
execution, and record the reliability warning explicitly in the maintenance
decision. Expansion does not repair that drive or replace its replacement plan.
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
Those exceptions were recorded, not repaired by the resize. Keep stopped
workloads down pending coordinated recovery; capacity growth is not incident repair.

## Selected target sizes

The user selected **150GiB backing zvols per host** for future buffer.
Proxmox3 is complete; repeat only on proxmox2-old after its host-specific
preflight. There is no need for an intermediate 128GiB step on the peer:
grow its confirmed current size directly to **150GiB = 161061273600 bytes**.
Preserve the two-replica policy; record and recover existing failed/missing
replicas rather than assuming the configured count proves two good copies.

| Host | Current backing device | Current Longhorn filesystem maximum | Recommended backing zvol | Approximate increase |
| --- | ---: | ---: | ---: | ---: |
| proxmox2-old | ~80GiB; verify exact bytes on host | 78.19GiB | **150GiB — next target** | **+70GiB** |
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

- Completed production requests: **38GiB per host** with two replicas overall.
- Remaining targets: Docker Mailserver **28.75GiB**, Mailpile **9.25GiB**.
- Mailpile's unverified staging already reserves **9.25GiB per host**. Reuse it
  only after a successful fresh copy/verification; do not count it twice.
- Additional nominal allocation to finish, if staging is reused: **28.75GiB per
  host**, all for Mailserver. The historical smaller-host shortfall was
  **5.64GiB**; repairing missing replica placements changes the live budget.
- After all migrations: **76GiB production requests per host**, plus approximately
  0.01/0.02GiB of older tests: **76.01/76.02GiB scheduled**. Creating another
  Mailpile staging pair temporarily adds 9.25GiB per host until old staging is
  deliberately removed; this is not included in the steady-state total.

Raw zvol size is not identical to Longhorn `storageMaximum`. The completed
150GiB grow on proxmox3 exposed **147.09GiB**. Expect roughly 147GiB on the peer,
but measure the actual result rather than forcing an exact filesystem size.

| Backing zvol per host | Estimated filesystem maximum | Nominal room after all migrations, current fixed reservations (node2 / node3) | Room if reserving 10% on both hosts instead |
| --- | ---: | ---: | ---: |
| **150GiB selected** | **~147.09GiB** | **~63.3 / 71.1GiB** | **~56.4GiB each** |

Longhorn reservations are byte amounts on existing disks: enlarging the zvol
must not be assumed to recalculate them as 10%. The procedure below preserves
existing values. Standardizing reservations is a **separate policy decision**.
The 10% column is an optional scenario, not part of the resize instructions.

150GiB gives substantial nominal growth room. A physical planning example is
current largest-host used space (~25.31GiB) + all remaining target sizes (38GiB,
conservatively allowing for data not yet in staging) + **10GiB actual data growth
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
or sparse allocation as guaranteed capacity. Proxmox3 passed this preflight;
the peer needs a new pool budget before repetition.

**Peer-specific physical limit:** recent peer samples showed an approximately
236GiB pool with only ~53GiB free. A 20% pool margin is about 47GiB, leaving
only ~6GiB of additional physical allocation above that floor. A sparse 80 →
150GiB virtual resize does not reserve the added 70GiB and does not make that
growth physically available. Include other datasets/VMs and expected Longhorn
data/snapshot growth in the peer decision; its replacement-drive capacity may
need to increase. Do not admit new migrations merely because `storageMaximum`
increases. Re-measure rather than treating those dated samples as current.

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

Do not repeat the resize on proxmox3: it is already at 150GiB. Do not run
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
measured per-host budgets, review the proposed cap, then plan Mailserver before
Mailpile. Keep original local rollback data until migration acceptance.

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
