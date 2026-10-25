# Expand Longhorn host storage — sizing proposal and procedure

Prepared 2026-10-25 after BookStack migration. **Documentation only: no disks,
filesystems, reservations, PVCs or migration caps were changed.**

## Active incident — expansion on hold

The [2026-10-25 I/O incident log](io-pressure-incident-2026-10-25.md) records
repeated API/k3s failures, severe storage stalls, runtime workload stops, and a
confirmed **NVMe temperature alarm on proxmox2-old**: composite 73.85 C with an
exposed high threshold of 69.85 C, plus a separate sensor reporting 93.85 C.
Thermal throttling is not yet proven. Read that log before maintenance, confirm
the cooling/temperature and storage problems are resolved, and revalidate all
health/backup prerequisites below. A brief ready API window is not sufficient.
No host expansion has been performed as part of that incident investigation.

## Recommended sizes

Start with **128GiB zvols on both hosts**, preserving two replicas for production
volumes. This is a modest staged expansion, rather than the earlier 256/320GiB
proposal. Use **160GiB each** if backing-pool capacity is comfortable and greater
snapshot/growth headroom is desired. Neither recommendation authorizes a resize.

| Host | Current backing device | Current Longhorn filesystem maximum | Recommended backing zvol | Approximate increase |
| --- | ---: | ---: | ---: | ---: |
| proxmox2-old | ~80GiB, inferred; verify on host | 78.19GiB | **128GiB** | **+48GiB** |
| proxmox3 | 100GiB, observed locally | 97.87GiB | **128GiB** | **+28GiB** |

These are **per-host sizes**, not a shared 128GiB pool. Both hosts need capacity
for a full replica set. With two storage nodes/two replicas, extra capacity on
only one host does not remove the smaller host's limit.

The current layout is a dedicated zvol with ext4 directly on the whole device:

```text
ZFS pool -> dedicated zvol -> ext4 -> /var/lib/longhorn -> Longhorn replica files
```

The local host exposes `/dev/zvol/rpool/longhorn` as `/dev/zd0`, a 100GiB device.
Device numbers vary; discover the peer's actual dataset/device before modifying
it. Repository configuration also allows `/dev/zvol/MargokPool/longhorn`.
Do not assume both hosts use rpool or the same `/dev/zdN` number.

## Capacity calculation

Last verified Longhorn snapshot, after BookStack (2026-10-25 ~13:40 UTC):

| Host | Maximum GiB | Physically free GiB | Longhorn reservation GiB | Scheduled GiB | Nominal remaining GiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| proxmox2-old | 78.19 | 55.08 | 7.82 | 47.26 | 23.11 |
| proxmox3 | 97.87 | 72.56 | 0 | 47.27 | 50.60 |

A later refresh failed because the APIs were unstable, so these are dated
measurements, not an assurance of current health or current free space.

- Completed production requests: **38GiB per host** with two replicas overall.
- Remaining targets: Docker Mailserver **28.75GiB**, Mailpile **9.25GiB**.
- Mailpile's unverified staging already reserves **9.25GiB per host**. Reuse it
  only after a successful fresh copy/verification; do not count it twice.
- Additional nominal allocation to finish, if staging is reused: **28.75GiB per
  host**, all for Mailserver. The smaller host is short by **5.64GiB** today.
- After all migrations: **76GiB production requests per host**, plus approximately
  0.01/0.02GiB of older tests: **76.01/76.02GiB scheduled**. Creating another
  Mailpile staging pair temporarily adds 9.25GiB per host until old staging is
  deliberately removed; this is not included in the steady-state total.

Raw zvol size is not identical to Longhorn `storageMaximum`. Based on the
current filesystem ratio, 128GiB should expose roughly **125GiB**; measure the
actual result. Using 125GiB for conservative arithmetic:

| Backing zvol per host | Estimated filesystem maximum | Nominal room after all migrations, current fixed reservations (node2 / node3) | Room if reserving 10% on both hosts instead |
| --- | ---: | ---: | ---: |
| 128GiB | ~125GiB | ~41.2 / 49.0GiB | ~36.5GiB each |
| 160GiB | ~156GiB | ~72.2 / 80.0GiB | ~64.4GiB each |

Longhorn reservations are byte amounts on existing disks: enlarging the zvol
must not be assumed to recalculate them as 10%. The procedure below preserves
existing values. Standardizing reservations is a **separate policy decision**.
The 10% column is an optional scenario, not part of the resize instructions.

128GiB gives substantial nominal growth room. A physical planning example is
current largest-host used space (~25.31GiB) + all remaining target sizes (38GiB,
conservatively allowing for data not yet in staging) + **10GiB actual data growth
+ 10GiB additional local snapshot/churn** = ~83.31GiB. On a ~125GiB filesystem,
that leaves ~41.69GiB free (~33%). This is a scenario, not a growth forecast:
re-measure mail, snapshot use and staging contents before execution.

Requested capacity, actual replica/snapshot bytes and filesystem free space
must all be tracked. If every requested production GiB eventually fills,
76GiB + 10GiB growth + 10GiB snapshots = 96GiB, which leaves less than 25% free
on ~125GiB. Expand earlier in that case. The **160GiB option** accommodates a
stricter example: 76GiB fully used + 25% data growth (19GiB) + 15GiB local
snapshots = 110GiB, leaving ~46GiB (~29%) free on ~156GiB.

This explains why **128GiB is the budget-conscious starting recommendation**,
and **160GiB is the more comfortable option**, not a requirement to buy disks.
Neither includes unlimited snapshot retention or a full duplicate of every
volume for simultaneous restore tests. Run small restore tests sequentially.

## Admission policy and underlying pool capacity

The old **55GiB production migration cap** cannot cover the completed 76GiB
plan. Propose a reviewed **100GiB production-request cap per host** after resize;
that permits the migration and 24GiB of additional requested growth. Admit a
change only if both hosts also pass nominal scheduling and physical-space gates.
That cap alone does not guarantee space for snapshots or fully used volumes.
It remains a proposal; this document does not lift the current 55GiB cap.

A sparse zvol's size is virtual capacity, not guaranteed backing-pool space.
Before choosing 128/160GiB, inspect each pool, competing VMs/datasets, quotas,
reservations and retained ZFS snapshots. Plan for the same worst-case data and
churn on both pools; keep an additional pool-level operating margin (use 20% as
a planning floor, more if write latency warrants it). Do not count compression
or sparse allocation as guaranteed capacity. Pool free space has not been
revalidated with root access for this proposal, so no disk purchase requirement
or guarantee that either option fits the backing pools is asserted.

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
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n longhorn-system get nodes.longhorn.io -o yaml
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n longhorn-system get volumes.longhorn.io
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
Set `longhorn_dataset` to the verified dataset from step 1. For the local host,
`rpool/longhorn` was observed; verify it again. Use **128G** for the recommended
first step or **160G** if the reviewed pool budget supports the larger option.
OpenZFS size suffixes here are binary units (GiB).

```bash
# Set these only after matching the mount, zvol and underlying device.
longhorn_dataset='rpool/longhorn'  # EXAMPLE: peer may use a different pool
longhorn_device="/dev/zvol/$longhorn_dataset"
longhorn_target_bytes=$((128 * 1024 * 1024 * 1024))
longhorn_current_bytes=$(sudo zfs get -Hp -o value volsize "$longhorn_dataset")

# Refuse shrink or a no-op; inspect rather than forcing another command.
if [ "$longhorn_current_bytes" -ge "$longhorn_target_bytes" ]; then
  log_resize 'STOP: current zvol is already at or above the requested target'
else
  log_resize "GROW START $longhorn_dataset: $longhorn_current_bytes -> $longhorn_target_bytes bytes"
  if sudo zfs set "volsize=$longhorn_target_bytes" "$longhorn_dataset"; then
    sudo udevadm settle
    longhorn_visible_bytes=$(sudo blockdev --getsize64 "$longhorn_device")
    if [ "$longhorn_visible_bytes" -eq "$longhorn_target_bytes" ]; then
      log_resize 'ZVOL GROW VERIFIED; starting ext4 online grow'
      if sudo resize2fs "$longhorn_device"; then
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

For 160GiB change the target arithmetic to 160 before executing. Do not run
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
