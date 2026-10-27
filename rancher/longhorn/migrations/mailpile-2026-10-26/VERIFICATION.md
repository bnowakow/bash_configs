# Mailpile verification progress and limits

**Latest observation:** 2026-10-27T19:51:28+00:00 staged-data revalidation 71.8% (7067/9837.56 MiB); cap 1024 KiB/s; paused=False; local={'some': 0.0, 'full': 0.0}; peer={'some': 0.07, 'full': 0.04}; alert=False. Full inventory, independent restore verification and cutover remain pending.

The user requested documenting the verification and reporting its percentage
**every minute** while this migration is monitored. Keep applications stopped
until migration validation succeeds, then restore their Fleet desired state.
No completed migration is claimed from the copied-byte counter alone.

## Progress denominators

Aggregate stopped-source totals measured27October2026,18:20UTC, without reading
message contents, are stored in [verification-totals.json](verification-totals.json):

| Tree | Unique regular-file bytes | Entries | Unique regular files |
|---|---:|---:|---:|
| Data | 10,315,431,773 (~9.61GiB) | 78,230 | 78,079 |
| Keys | 600 | 3 | 3 |

Report the active verification stage with its percentage:

1. **Staged-data revalidation:** `RESUME_VALIDATION rechecked_MiB` divided by
   the measured data-byte total. Report this as a byte-progress percentage;
   the complete inventory/manifest checks remain required. Existing files are
   compared with the stopped source before reuse; damaged/partial files are
   repaired. A worker restart resets this verification pass, not copied data.
2. **Metadata inventories:** `INVENTORY_PROGRESS` reports exact checked/total
   entries and percentage for each source/target pass. Name the tree/pass.
   Two equal-size passes can be summarized as source percent/2, then
   50+target percent/2. Do not present a per-pass percentage as overall completion.
3. **Independent NAS restore:** completed backup/restore and keyring checks are
   separate gates. `HASH_PROGRESS` reports checked/expected bytes and inventory
   entries. Full hashes, metadata, ownership, timestamps and links must match
   the private manifest before the restore is accepted.
4. **Final source check and cutover:** recheck stopped-source inventory, sole
   writer/API guards, target replica health, actual mounts, Fleet deployment
   state, rollout, unchanged configuration/secrets and service endpoints.

Only STATE phasecomplete after final validation authorizes application
restoration. `restore-fleet.py` repeats final checks and restores gradually to
verified Fleet manifests; support services outside Fleet use their saved state.
RESTORATION.json records successful restoration. See [MAINTENANCE.md](MAINTENANCE.md).

## Current monitored limits and history

The original metadata limiter was fixed20entries/s. Its two data inventories
would take about130minutes at that pacing; earlier~20–28% reports were estimates
from elapsed time, not emitted entry counts. At user request the worker was
checkpointed with all copied files preserved, then resumed with new controls
and explicit inventory progress. Staged contents must be revalidated afresh.

The first verification trial requested8MiB/s revalidation,2MiB/s restore hashes
and100metadata entries/s. It triggered the pressure guard around18:01UTC
(peer full PSI2.17%), causing a pause and conservative fallback. No data was
lost or activated. At18:11UTC the verification was adjusted **live**, without
another worker restart, to the moderate settings below:

| Control | Moderate-trial requested limit (later reduced) |
|---|---:|
| New/repair copying | 256KiB/s |
| Existing staged-data revalidation | 4096KiB/s (4MiB/s) |
| Later restored-data hashing | 1024KiB/s (1MiB/s) |
| Metadata entries | 40/s |

These are monitored limits, not guaranteed throughput. Read RATE.json and worker
output for the latest accepted settings. [TRANSFER-CAPS.md](TRANSFER-CAPS.md)
records every accepted change, including automatic reductions and outcomes.

`rate-watch.py` samples both hosts every15seconds. Either host PSI some>10% or
full>2%, insufficient peer backing-pool headroom, or unavailable telemetry pauses
work and reduces limits conservatively. Three low samples are required before
resume, and reduced limits are retained. It applies configuration to transfer
and restore helpers as they become Ready and continues through verification.
Native Longhorn backup/restore traffic has separate concurrency controls; these
Python limits do not directly cap native engine traffic.

All controls are now live-adjustable in the helpers' /tmp/mailpile-rate.json:
copyKiBps, reuseKiBps, verifyKiBps, metadataEntriesPerSecond, and pause. For future
tuning, replace only the rate-monitor process using the intended CLI options;
**do not restart the copy/coordinator merely to change metadata or hashing caps**.
The byte-limit range is64–16384KiB/s; metadata5–500entries/s. Keep pressure guards.

Validation of the control changes included full copy/resume/restore fixtures,
valid-file reuse, corruption repair, sparse files, hardlinks, symlinks, FIFO,
metadata equality, stale-entry cleanup, independent live byte limits and live
metadata pacing. Original claims and source0 remain protected throughout.
