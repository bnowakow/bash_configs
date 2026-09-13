# MargokPool RAIDZ3 incident — 2026-09-13

## Current condition

`MargokPool` is a single seven-member `raidz3-0` vdev. It remains importable and
reports `ONLINE`, but three members are faulted. RAIDZ3 tolerates exactly three
unavailable members, so this vdev currently has **no remaining fault tolerance**.

At the time of observation, ZFS reported no known unrecoverable data errors. A
resilver started at 15:47:18, but scanned about 2 TB while issuing essentially no
reconstruction writes. Do not assume this restores redundancy while members remain
faulted.

### ZFS member state

From `zpool status -PL MargokPool`:

| Member | State | Error counters |
|---|---|---:|
| `/dev/sdg1` | ONLINE | 0 / 0 / 0 |
| `/dev/sdh1` | ONLINE | 0 / 0 / 0 |
| `/dev/disk/by-partuuid/e1a6b162-fe08-4e9b-8cd8-5230f7db7e82` | FAULTED | 627 / 1.35K / 11 |
| `/dev/disk/by-partuuid/8b97df37-6299-4461-8661-2036b75c37f8` | FAULTED | 1.53K / 2.27K / 0 |
| `/dev/sdb1` | FAULTED | 4 / 1.05K / 0 |
| `/dev/sdl1` | ONLINE | 0 / 0 / 0 |

The two `by-partuuid` links did not exist after reboot. Base disks `sdc` (serial
`WWZ7DHBP`) and `sdk` (serial `WWZ5T8RZ`) were visible, but their ZFS
partitions/labels were unavailable. `sdb` is serial `ZJV5RCAK`.

## Evidence and likely cause

Kernel logs show an ongoing shared SAS-path failure, not merely historical errors:

- `mpt3sas_cm0` and earlier `mpt3sas_cm1` repeatedly logged physical-layer (`PL`)
  events: `log_info(0x31110e03)` and `log_info(0x31120100)`.
- `sdb`, `sdc`, and `sdk` returned `Sense Key: Not Ready` and read/write I/O errors.
- The kernel reported `Power-on or device reset occurred` for affected devices.
- At 16:13–16:14, new `mpt3sas_cm0` events and `sdb` `Not Ready`/I/O errors continued.

This supports a shared failure in the HBA/controller, SAS cable, backplane/expander,
or power distribution, rather than three independent disk failures.

## Immediate safety actions

1. Stop pool-writing workloads (apps, VMs, iSCSI clients, and other shares) and copy
   irreplaceable data to independent storage if possible.
2. Do **not** scrub, clear errors, run `zpool online`, use TrueNAS **Replace**, or use
   `zpool attach`, `zpool add`, or any **Force**/wipe operation while errors continue.
3. Perform a controlled shutdown:

   ```sh
   shutdown -h now
   ```

4. With power off, inspect/reseat the `sdb` drive carrier/slot, SAS cables, HBA
   connections, backplane/expander connections, and power connectors. Inspect the
   entire SAS chain, including both `mpt3sas` controllers.

## Recovery after the hardware path is stable

1. Boot and verify the affected partitions return:

   ```sh
   ls -l /dev/sdb1 /dev/sdc1 /dev/sdk1
   zpool status -PL MargokPool
   ```

2. ZFS may rediscover the original members automatically. If the original disks and
   partitions exist but still show `FAULTED`, bring the existing members online one at
   a time, checking status after each:

   ```sh
   zpool online MargokPool 3924186910385107328
   zpool online MargokPool 4990597411752621388
   zpool online MargokPool 17069936623140461086
   ```

   `zpool online` does not format, add, attach, or replace a disk. Do not run it if a
   device path is absent or kernel I/O errors continue.

3. Wait for all members to be `ONLINE` and the resilver to finish:

   ```sh
   zpool status -PL MargokPool
   ```

4. Only after hardware and pool stability is confirmed, clear historic counters:

   ```sh
   zpool clear MargokPool
   ```

## Monitoring commands

```sh
journalctl -k -b --since '15 minutes ago' --no-pager -o short-iso | \
  grep -Ei 'mpt3sas_cm[01]|Power-on or device reset|I/O error|Not Ready|timeout|link.*down'

journalctl -kf -o short-iso | \
  grep --line-buffered -Ei 'mpt3sas_cm[01]|Power-on or device reset|I/O error|Not Ready|timeout|link.*down'
```

Stop the live monitor with `Ctrl-C`. New `mpt3sas` events, `Not Ready`, I/O errors,
or increasing ZFS error counters mean the SAS path is still unstable.
