
  ## PlexPool

  ### Expansion

  The raidz1-0 expansion completed on 18 October 2026 at 00:18 CEST. ZFS reported 12.4T copied in 13:48:08. The resulting RAIDZ1 vdev has five drives.

  A scrub completed later that morning, repairing 0B with 0 errors. PlexPool was ONLINE with no known data errors in every recorded measurement.

  ### Rewrite

  Files under /mnt/PlexPool/plex were rewritten with:

  zfs rewrite -r /mnt/PlexPool/plex -v > zfs_rewrite.out

   Recorded at (CEST)    Stage                                            Pool allocated    Pool free    Pool capacity    plex used    plex available    plex referenced
  ━━━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━  ━━━━━━━━━━━  ━━━━━━━━━━━━━━━  ━━━━━━━━━━━  ━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━━
   18 Oct 11:25          Initial measurement                                       12.4T        5.82T              67%        8.24T             3.75T              7.99T
  ────────────────────  ───────────────────────────────────────────────  ────────────────  ───────────  ───────────────  ───────────  ────────────────  ─────────────────
   18 Oct 14:50          After first rewrite                                       14.5T        3.68T              79%        9.66T             2.32T              7.80T
  ────────────────────  ───────────────────────────────────────────────  ────────────────  ───────────  ───────────────  ───────────  ────────────────  ─────────────────
   18 Oct 15:09          After snapshot cleanup, before second rewrite             11.7T        6.47T              64%        7.80T             4.19T              7.80T
  ────────────────────  ───────────────────────────────────────────────  ────────────────  ───────────  ───────────────  ───────────  ────────────────  ─────────────────
   19 Oct 09:35          After second rewrite                                      10.7T        7.51T              58%        7.11T             4.88T              7.11T

  Overall result: Pool free space increased by 1.69T (5.82T → 7.51T) between the initial and final measurements. Available space on PlexPool/plex increased by 1.13T.

  During the second rewrite period, pool free space increased by 1.04T and plex referenced space decreased by 0.69T. These are net changes; snapshot deletion and normal
  file activity mean the rewrite’s contribution cannot be isolated exactly.

  ### Snapshots

  Automatic snapshots were observed on PlexPool and PlexPool/plex. Snapshots can retain old blocks during a rewrite. Two snapshots dated 19 October were listed afterward;
  deletion commands were provided, but their removal was not independently verified. An enabled automatic snapshot task may create new snapshots.

  ### Snapshot removal script (remove-snapshots.sh)


  #!/bin/bash -x

  POOL_NAME="PlexPool"
  DIRECTORY_NAME="plex"
  DATASET_NAME="${POOL_NAME}/${DIRECTORY_NAME}"
  SNAPSHOT_SCOPE="$POOL_NAME"  # Whole pool; use "$DATASET_NAME" for plex only
  SNAPSHOT_LIST="/tmp/${POOL_NAME}-snapshots-to-delete.txt"

  zfs list -r -t snapshot "$SNAPSHOT_SCOPE"
  zpool get freeing "$POOL_NAME"
  zpool list -o name,alloc,free "$POOL_NAME"

  echo "starting remove"

  zfs list -H -r -t snapshot -o name "$SNAPSHOT_SCOPE" > "$SNAPSHOT_LIST" || exit 1
  cat "$SNAPSHOT_LIST"

  while IFS= read -r snap; do
    zfs destroy "$snap" || exit 1
  done < "$SNAPSHOT_LIST"

  echo "finished remove"

  zfs list -r -t snapshot "$SNAPSHOT_SCOPE"
  zpool get freeing "$POOL_NAME"
  zpool list -o name,alloc,free "$POOL_NAME"


  With these values, the measurement command writes PlexPool-plex-space-after.txt. The removal script targets snapshots of PlexPool/plex and its child datasets.


  ### Capture the post-rewrite measurement

  POOL_NAME="PlexPool"
  DIRECTORY_NAME="plex"
  DATASET_NAME="${POOL_NAME}/${DIRECTORY_NAME}"

  {
    date
    zpool status "$POOL_NAME"
    zpool list -o name,size,alloc,free,cap,frag "$POOL_NAME"
    zfs list -o name,used,avail,refer "$DATASET_NAME"
  } > "${POOL_NAME}-${DIRECTORY_NAME}-space-after.txt"



## MargokPool

### Scope, dates, and units

This section records the MargokPool investigation on 8–10 October 2026 and a live
refresh on 19 October 2026 at approximately 10:08 CEST. Earlier measurements came
from the investigation transcript; the refresh came from live ZFS commands.
Values such as `43.7T` are ZFS binary display units (approximately TiB), rounded by
the command. Byte counts and decimal TB are identified explicitly. Small changes
can reflect rounding or normal file activity, and independently queried figures
are not an atomic measurement.

OpenZFS userland and kernel module both reported `2.3.9-1` during the investigation
and on 19 October. `zpool status` reports health and expansion/scrub history;
capacity comparisons below use `zpool list` and `zfs list`.

### Expansion and health

MargokPool has one six disk `raidz3-0` vdev, with drives reporting approximately
`7.28T` each and total raw pool size `43.7T`. Pool history records a disk attach on
24 December 2025 at 16:53:33. Expansion completed on 26 December 2025 at 06:14:47,
copying `29.6T` in 1 day 13:21:14. The observed single disk addition to the current
six disk vdev is consistent with a five to six disk RAIDZ3 expansion.

The ideal large block data fractions are:

| Layout | Data and parity columns | Ideal data fraction |
| --- | --- | ---: |
| Five disk RAIDZ3 | 2 data + 3 parity | 40% |
| Six disk RAIDZ3 | 3 data + 3 parity | 50% |

These are simplified fractions. Sector rounding, small blocks, metadata,
compression, and allocation padding affect actual consumption. Expansion spreads
existing blocks over the enlarged vdev while retaining their old logical stripe
width. Newly allocated blocks can use the wider layout.

On 8 October, status showed a completed `102G` resilver with zero errors on
13 September 2026. On 19 October, the latest scan was a scrub completed on
18 October at 13:35:24, repairing `0B` in 13:35:09 with zero errors. The pool was
ONLINE, with all read, write, and checksum error counters zero and no known data
errors in the recorded status checks.

### Space measurements and snapshot cleanup

| Recorded stage | Raw pool allocated | Raw pool free | Pool dataset USED | Dataset AVAIL | archive USED / REFER | archive snapshot space |
| --- | ---: | ---: | ---: | ---: | --- | ---: |
| Initial supplied figures, 8 Oct | 28.6T | 15.1T | 11.4T | 5.89T | Not supplied | Not supplied |
| Live inspection, before cleanup, 8 Oct | 28.5T | 15.1T | 11.4T | 5.90T | 9.49T / 8.35T | 1.14T |
| After deleting 1,059 snapshots, 8 Oct | 21.5T | 22.1T | 8.59T | 8.69T | 8.35T / 8.35T | 0B |
| During rewrite, after midnight snapshot, 9 Oct | About 27.0T | About 16.7T | Not captured | 6.43T at later sample | 10.6T / about 8.36T | 2.23T at later sample |
| After deleting 57 snapshots, 9 Oct; reclaim still running | 22.9T | 20.8T | Not captured | 8.58T | 8.36T / about 8.36T | 0B |
| Later 9 Oct; reclaim finished | 21.6T | 22.1T | Not captured | 8.67T | 8.36T / about 8.36T | 0B |
| Rewrite no longer running; new midnight snapshot, 10 Oct | 23.7T | 20.0T | Not captured | 7.84T | 9.19T / about 8.36T | 847G |
| After deleting 54 snapshots, 10 Oct | 21.6T | 22.1T | 8.60T at subsequent sample | 8.66T | 8.36T / about 8.36T | 0B |
| Live refresh, 19 Oct | 22.6T | 21.0T | 9.02T | 8.25T | 8.75T / 8.42T | 337G |

Rows describing the same period can contain values captured seconds or minutes
apart. In particular, the 9 October snapshot grew while it was being inspected.

The first cleanup increased raw pool free space by approximately `7.0T` and
dataset availability by approximately `2.79T`. This was predominantly the release
of snapshot retained data; it must not be credited to the subsequent rewrite.
Between the first cleanup and the 10 October cleanup, the rounded figures showed
no material net capacity gain from the rewrite period. Concurrent file activity
and unverified rewrite completion prevent a precise attribution.

The initial 1,059 snapshots were distributed as follows:

| Dataset tree | Snapshot count |
| --- | ---: |
| Pool root | 31 |
| .ix-virt | 12 |
| .system | 146 |
| .truenas_containers | 3 |
| archive | 31 |
| home | 31 |
| ix-apps | 802 |
| longhorn | 3 |

Summing `usedbysnapshots` across filesystem and volume datasets gave
`3,073,122,690,048` bytes, about `2.795 TiB`. The largest contributors were
`MargokPool/ix-apps/app_mounts/minio/export` (`1.60T`) and `MargokPool/archive`
(`1.14T`). MinIO's live referenced data was only `31.9G`, so much of its retained
snapshot data was absent from the live filesystem.

The sum of individual snapshots' `USED` values was only
`439,356,451,584` bytes. It understated collective retention because blocks shared
by several snapshots are not charged as exclusive space to any one snapshot.
Dataset `usedbysnapshots` is the appropriate collective accounting measure;
parent `usedbysnapshots` does not include snapshots of child datasets. Do not add
parent dataset USED to child USED when calculating a pool total.

All three requested cleanup operations were verified afterward with zero pool
snapshots remaining. Preflight checks found no snapshot holds or clone
dependents. On 9 October, `freeing` was initially `310G`, then reached zero. On
8 and 10 October, final checks also showed `freeing=0`.

Automatic snapshot creation remained enabled: `archive@auto-2026-10-09_00-00`
and `archive@auto-2026-10-10_00-00` retained blocks replaced after midnight. This
was directly observed alongside rising allocation. Deleting the snapshots
released that retention. Deleting existing snapshots does not disable the task.

On 19 October, MargokPool again had **269 snapshots**. Across its datasets,
`usedbysnapshots` totaled `372,804,549,120` bytes (about `347.2 GiB`), including
about `337G` on `archive`. Root dataset `USEDSNAP=0B` did not mean the whole pool
had no snapshots. No further snapshots were deleted for this documentation task.

### Rewrite commands, coverage, and outcome limits

The observed commands were:

```bash
sudo zfs rewrite -rx /mnt/MargokPool/archive
sudo zfs rewrite -rxv /mnt/MargokPool/archive > zfs-rewrite.output
```

The first process was later replaced by the verbose run. The verbose process was
observed from 8 through 9 October and was absent by the 10 October check. Its
process ID was `1441371`, with a parent sudo process `1441370`.

`-r` traverses directories, `-x` prevents crossing filesystem mount points, and
`-v` prints successfully rewritten file names. The argument is a filesystem path.
This command targeted files on `MargokPool/archive`; it did not constitute a
rewrite of the entire pool. The root dataset, `home`, app datasets under
`/mnt/.ix-apps`, system datasets, and the `longhorn` volume were not established
as covered by this command. Root dataset REFER was approximately `118G`.

The redirected output was opened in:

```text
/mnt/MargokPool/home/sup/code/zfs-inplace-rebalancing/zfs-rewrite.output
```

It was unlinked while the process still held it open. While running, its content
remained readable through `/proc/1441371/fd/1`; when the process exited that
access disappeared. Its final output, stderr, exit code, and exact finish time
were not captured. No matching rewrite command was found in the queried pool
history, which also did not establish completion or failure. **The disappearance
of the process is not proof of a successful full traversal.** No earlier rewrite
covering all relevant data was verified either. No rewrite process was running
at the 19 October refresh.

The last recorded running sample contained **2,129,559 completed file entries**,
with cumulative process reads of approximately **10.66 decimal TB**. It was
processing an Aperture photo library. Other observed data included large backup
tar files, Lightroom photos, Proxmox Backup Server chunks, Windows backup trees,
and Reolink video files. File count is a poor estimate of remaining runtime for
this mixture of sizes.

Earlier progress estimates of approximately 1–39% compared the apparent sizes of
logged files with ZFS REFER. A later estimate of approximately 83% compared
process disk reads with REFER. **These were not reliable completion percentages
and should not be used as final progress or coverage evidence.** REFER is a ZFS
space accounting value; file apparent sizes have different compression, sparse
file, hardlink, and metadata behavior. Process I/O includes additional reads and
eventually exceeded the dataset's reported size. The increasing log count and
changing current file established activity, but no valid total traversal size
or ETA was obtained.

`zfs rewrite` in this installed version has no native percentage or ETA display.
`-v` adds a line per completed file, generally inexpensive for large files but
potentially noticeable for very large numbers of small files or slow output.
It does not add progress to `zpool status`. Pool I/O and allocation can be
monitored separately. For a future run, retain stdout and stderr, record the
exit code and timestamps, and capture before/after space figures. Run from a
persistent terminal and prevent scheduled snapshots from retaining the whole
rewrite if immediate space recovery is the intended result.

### Accounting interpretation and recoverable capacity

Before initial cleanup, `zpool FREE=15.1T` and `zfs AVAIL=5.90T` were plausible
because raw free space includes the space required for parity and ZFS reports
dataset availability with further allocation/accounting deductions. The pool
had no material reservation or quota explaining the pool-wide gap: the only
non-default quota found was `1G` on `.system/cores`. Reservations and
refreservations were none, compression was generally lz4, and archive recordsize
was `128K`. The initial pool/archive compression ratios were about `1.07x`.
Pool `freeing` and `leaked` were zero and no checkpoint was present at that check.

At the snapshot-free 10 October sample:

```text
zpool:  ALLOC 21.6T, FREE 22.1T
zfs:    pool USED 8.60T, AVAIL 8.66T
```

`21.6T * 0.40 = 8.64T` and `22.1T * 0.40 = 8.84T`, close to the reported dataset
values after accounting deductions. On 19 October the precise queried ratios
were approximately **39.84% for pool USED / raw ALLOC** and **39.25% for AVAIL /
raw FREE**. They remain close to the original five disk RAIDZ3 fraction.

This is evidence of the reported accounting relationship. It does not measure
the fraction of blocks still using the old stripe width, prove a rewrite failed,
or establish that all data has the old physical layout. Dataset accounting can
retain a conservative relationship after RAIDZ expansion and a rewrite;
similar behavior has been reported upstream. The additional effect of old
blocks cannot be separated from accounting and overhead using these listings
alone. The ideal current-width estimate `raw FREE * 0.50` is a geometry reference,
not a guaranteed amount of writable data or a guaranteed recovery target.

For sufficiently large old five disk blocks with fixed compressed payload B,
the simplified raw requirement changes from `2.5 * B` to `2.0 * B`: a potential
20% reduction of those blocks' old raw allocation. This is not a forecast for
the whole pool. The eligible old-block amount, complete rewrite coverage, and
effects of padding and metadata were not measured, so no reliable additional
recoverable TiB figure was established.

Snapshot referenced blocks may remain allocated when live files are rewritten.
Files retained only by snapshots are not visited by a live path traversal. A
repeat rewrite after successful coverage of the same files would not have an
established RAIDZ space benefit unless relevant blocks or properties changed.
The persistent raw/usable gap alone is not a reason for another full rewrite.

### zfs rewrite versus zfs-inplace-rebalancing

The markusressel script copies each file, deletes the original, and renames the
copy. Both approaches can force new allocation using the current layout, and
both can retain old blocks through snapshots. The script's README recommends
checking `zfs rewrite` first. The native command performs the rewrite through
ZFS with atomic read/rewrite semantics and avoids the script's file replacement
and hardlink handling workflow.

No extra RAIDZ capacity benefit from running the script after a successful native
rewrite was demonstrated. No execution of the script on MargokPool was verified;
the output file's location in that project's directory is not evidence of use.
For the installed 2.3.9 interface, no `-P` option was advertised. Rewritten blocks
appear changed to subsequent incremental sends in this version, so a future run
should account for replication traffic as well as local space.

## Comparison: MargokPool and PlexPool

### Layout and expansion history

Live pool history checked on 19 October adds context to the PlexPool section:
PlexPool was created as `PlexPoolNew` with **three RAIDZ1 disks on 2 May 2025**,
expanded to four disks on **19 April 2026**, and expanded to five disks beginning
**17 October 2026 at 10:30:06**. The latest expansion completed on 18 October at
00:18:13. Drive replacements in the history are separate from those expansions.

| Property | MargokPool | PlexPool |
| --- | --- | --- |
| Current topology | One six disk RAIDZ3 vdev | One five disk RAIDZ1 vdev |
| Expansion history established here | Five to six disks, December 2025 | Three to four, April 2026; four to five, October 2026 |
| Initial data fraction relevant to observed accounting | 2/5 = 40% | 2/3 = 66.7% |
| Current ideal large block data fraction | 3/6 = 50% | 4/5 = 80% |
| Latest expansion bytes copied | 29.6T | 12.4T |
| Latest expansion duration | 1 day 13:21:14 | 13:48:08 |
| Latest expansion completion | 26 Dec 2025 06:14:47 | 18 Oct 2026 00:18:13 |
| Latest scrub, verified 19 Oct | 18 Oct; 0B repaired, zero errors | 18 Oct; 0B repaired, zero errors |
| Rewrite target | `/mnt/MargokPool/archive` | `/mnt/PlexPool/plex` |
| Rewrite completion evidence | Last process gone by 10 Oct; exit and complete coverage unverified | Existing PlexPool section records measurements after first and second rewrites |

Durations describe expansion/reflow operations, not rewrite runtimes. Different
parity levels, disk sizes, workloads, and prior expansions prevent using these
two durations as a controlled performance comparison.

### Results from the recorded rewrite periods

| Comparison | MargokPool | PlexPool |
| --- | --- | --- |
| Initial recorded raw FREE | 15.1T, before large snapshot cleanup | 5.82T, before first recorded rewrite |
| Later historical raw FREE | 22.1T after cleanup and rewrite period, 10 Oct | 7.51T after second recorded rewrite, 19 Oct 09:35 |
| Change between those figures | About +7.0T; largely explained by initial snapshot deletion | +1.69T net across the recorded period |
| Availability change across those figures | About +2.77T, 5.89T to 8.66T | +1.13T, 3.75T to 4.88T |
| More informative rewrite comparison | After initial cleanup to after final cleanup: rounded FREE stayed near 22.1T | After cleanup/before second rewrite to after second: FREE rose 6.47T to 7.51T (+1.04T), REFER fell 7.80T to 7.11T (-0.69T) |
| Snapshot interference | Midnight snapshots repeatedly increased allocation; directly verified | First rewrite period increased allocation while snapshots retained blocks; later cleanup released space |

The PlexPool data shows a measurable net reduction during the second rewrite
period. MargokPool data did not demonstrate a comparable net reduction after
cleanup, and its traversal completion remains unverified. Normal writes,
deletions, and snapshot changes prevent treating either set as a controlled
measurement of rewrite savings alone. The 19 October refresh is a later workload
state, not a replacement for the historical before/after comparison.

### Live comparison on 19 October 2026, approximately 10:08 CEST

| Measurement | MargokPool | PlexPool |
| --- | ---: | ---: |
| Raw SIZE | 43.7T | 18.2T |
| Raw ALLOC | 22.6T | 10.7T |
| Raw FREE | 21.0T | 7.49T |
| Raw CAP | 51% | 58% |
| FRAG | 27% | 11% |
| Pool dataset USED | 9.02T | 7.13T |
| Dataset AVAIL | 8.25T | 4.86T |
| Main dataset USED | archive: 8.75T | plex: 7.13T |
| Main dataset REFER | archive: 8.42T | plex: 7.13T |
| Main dataset USEDSNAP | archive: 337G | plex: 0B |
| Total pool snapshot count | 269 | 0 |
| Pool USED / raw ALLOC, from byte values | 39.84% | 66.60% |
| AVAIL / raw FREE, from byte values | 39.25% | 64.93% |
| Health | ONLINE, zero reported errors | ONLINE, zero reported errors |

Both accounting ratios remain near their pools' original data fractions, despite
different observed rewrite outcomes. This demonstrates why matching `zpool`
and `zfs` numbers is not a useful rewrite success criterion. PlexPool's apparent
raw/usable gap persisted even as its raw allocation fell. For MargokPool,
snapshot cleanup produced the clearest measured space recovery.

MargokPool's reported free dataset space is reasonable relative to PlexPool
under the observed accounting assumptions. Its 8.25T AVAIL is close to
21.0T raw FREE multiplied by its original 40% data fraction (8.40T). PlexPool's
4.86T AVAIL is similarly close to 7.49T multiplied by its original two-thirds
fraction (about 4.99T). The small remaining differences are consistent with
additional space-accounting deductions. MargokPool also has more raw headroom
at 51% CAP than PlexPool at 58% CAP in this refresh.

This comparison supports the plausibility of MargokPool's AVAIL figure; it does
not verify full rewrite coverage or prove that all blocks use the current
geometry. Using current ideal fractions would instead give approximately 10.5T
for MargokPool and 5.99T for PlexPool, before other overhead. Neither number is a
guaranteed writable capacity or rewrite recovery target. Both pools retain a
similar conservative reporting pattern, while only PlexPool has a recorded
second-rewrite period showing a clear net allocation reduction.

The refreshed PlexPool snapshot count of zero independently resolves the earlier
section's uncertainty about whether its two 19 October snapshots were removed
by this refresh. This observation does not establish when or how they were
removed. MargokPool's renewed snapshots show that its automatic retention
schedule continued after the earlier cleanup operations.

Scope clarification for the existing PlexPool removal script: its actual
`SNAPSHOT_SCOPE="$POOL_NAME"` setting targets the whole pool and descendants,
including child dataset snapshots. The nearby original prose describing a
`plex`-only scope does not match that setting. Changing the setting to
`SNAPSHOT_SCOPE="$DATASET_NAME"` would target only that dataset tree.

### References and repeatable measurements

The pool histories, live command output, existing PlexPool notes, and October
8–10 MargokPool transcript are the measurement sources. The following upstream
references support the behavioral explanations; an issue report is evidence of
reported behavior, not a diagnosis of these particular pools:

- [OpenZFS RAIDZ layout and expansion](https://openzfs.github.io/openzfs-docs/Basic%20Concepts/Pool%20Structure/RAIDZ.html)
- [OpenZFS 2.3 zfs-rewrite manual](https://openzfs.github.io/openzfs-docs/man/v2.3/8/zfs-rewrite.8.html)
- [OpenZFS dataset properties and snapshot space accounting](https://openzfs.github.io/openzfs-docs/man/v2.3/7/zfsprops.7.html)
- [Upstream report of low AVAIL after expansion and rewrite, issue 18711](https://github.com/openzfs/zfs/issues/18711)
- [zfs-inplace-rebalancing README and native rewrite recommendation](https://github.com/markusressel/zfs-inplace-rebalancing)

For future comparisons, retain both readable and exact byte measurements and
record snapshots and background freeing at the same stage:

```bash
date --iso-8601=seconds
zfs version
zpool status MargokPool PlexPool
zpool list -p -o name,size,alloc,free,cap,frag MargokPool PlexPool
zfs list -p -o name,used,avail,refer,usedbysnapshots \
  MargokPool MargokPool/archive PlexPool PlexPool/plex
zfs list -p -r -t filesystem,volume -o name,usedbysnapshots MargokPool PlexPool
zfs list -p -r -t snapshot -o name,used,refer,creation MargokPool PlexPool
zpool get freeing,leaked,checkpoint MargokPool PlexPool
```
