# Mailpile transfer-cap history

All limits are KiB/s. Record every change, including automatic fallback; a
configured/requested limit is not sufficient evidence that the worker applied
it. COPY_PROGRESS/RATE_LIMIT_CHANGED show observed worker limits; ACTIONS.log
records monitoring, control writes and safety pauses. The monitor appends future
changes only after the live configuration update succeeds. Mark outcome later
from observed pressure, guard status and copy advancement. Times below are UTC.

| Time | Copy-cap change | Reason and observed result |
|---|---|---|
| 2026-10-26, preparation | Prepared4MiB/s →1MiB/s →256KiB/s | Successive user requests for stronger throttling. Historical preparation changes; no production copy ran at4 or1MiB/s. See HANDOFF history. |
| 2026-10-27 08:14 | Start at256KiB/s | Initial active stopped-source copy. Later progress verified with256KiB/s in worker output. |
| 2026-10-27 10:39 | 256 →512KiB/s | User requested a modest increase. Fixed-rate worker was checkpointed; verified-resume worker rechecked and reused valid staging files. COPY_PROGRESS confirmed512KiB/s; both hosts initially PSI0. Copy advanced to2567MiB at512 with no writer/API alert at12:15. |
| 2026-10-27 12:42 | 512 →256KiB/s, paused | Automatic fallback: local PSI15.68%some/15.05%full, peer0. Local pressure later peaked28.36%some/27.66%full at12:44. Copy paused; this burst was not proven to be caused by the cap. |
| 2026-10-27, after12:46 | Remained256KiB/s, resumed | Three low-pressure samples allowed resumption; monitor deliberately retained256. At13:02 both hosts PSI0 and COPY_PROGRESS showed3585MiB at256. |

## Subsequent live changes

The monitor appends accepted cap changes below. Requested768KiB/s trial is
pending until an accepted-change row and observed worker output confirm it.
Pause thresholds remain some>10% or full>2% on either host. Safety fallback is
256KiB/s; it does not automatically increase after recovery. Verification reads
remain512KiB/s. Native NAS backup/restore have separate concurrency controls.

| Time UTC | Copy-cap change | Reason / outcome at application |
|---|---|---|
| 2026-10-27T13:05:04+00:00 | 256 → 768 KiB/s | User-requested monitored cap trial; pause=False. See contemporaneous RATE MONITOR samples in ACTIONS.log. |
| 2026-10-27 13:07 | 768 KiB/s — trial observation | Worker COPY_PROGRESS confirmed768; verified progress3625→3712MiB over approximately2min. Local PSI0/0, peer0.08%some/0.02%full, no writer/API alert, free60.33GiB. Short observation passed; continuous monitoring remains active. |
| 2026-10-27T13:08:27+00:00 | 768 → 1024 KiB/s | User-requested monitored cap trial; pause=False. See contemporaneous RATE MONITOR samples in ACTIONS.log. |
| 2026-10-27 13:10 | 1024 KiB/s — trial observation | Worker confirmed1024 without copy restart; progress3754→3859MiB in about1.5min. Local PSI0.07%some/0.04%full; peer0.19%some/0.03%full; no writer/API alert, free60.28GiB. Short trial passed; pressure monitoring and256 fallback remain enabled. |
| 2026-10-27 13:14 | Requested further increase — not applied | Current worker ceiling1024KiB/s. A small increase requires restart/revalidation of~4GiB and may delay completion; user preference requested. Existing1024 retained while monitoring. Progress4070MiB; local PSI0/0, peer0.45%some/0.36%full, no guard alert. No cap change or copy restart performed. |
| 2026-10-27T13:20:00+00:00 | 1024 → 2048 KiB/s | User-requested monitored cap trial; pause=False. See contemporaneous RATE MONITOR samples in ACTIONS.log. |
| 2026-10-27T13:26:13+00:00 | 2048 → 3072 KiB/s | User-requested monitored cap trial; pause=False. See contemporaneous RATE MONITOR samples in ACTIONS.log. |
| 2026-10-27 13:41 | 3072 KiB/s — monitored outcome | Worker-confirmed live3MiB/s after2MiB resume; revalidated157→1174MiB. Peer full PSI mostly0.01–1.81%; one brief2.13% worker pause at13:40 resumed automatically. Local PSI0; no writer/API alert. Last peer full0.99%. Staged4332MiB retained; revalidation is not additional copied data. Continuous monitoring/fallback retained. |
| 2026-10-27T14:31:34+00:00 | 3072 → 256 KiB/s | Automatic safety reduction: pressure/headroom/telemetry guard; pause=True. See contemporaneous RATE MONITOR samples in ACTIONS.log. |
| 2026-10-27T16:34:53+00:00 | 256 → 1024 KiB/s | User-requested monitored cap trial; pause=False. See contemporaneous RATE MONITOR samples in ACTIONS.log. |
| 2026-10-27 16:37 | 1024 KiB/s — monitored outcome | User requested increase after long stable256 fallback. Worker confirmed1024 live; progress7627→7721MiB over about2min. Local full PSI peaked0.16%, peer0.06%, latest both0; no writer/API alert or pause. Other applications remain quiesced. Short trial passed; continuous monitoring retained. |
| 2026-10-27T17:57:02+00:00 | verifyKiBps: 512 → 2048; reuseKiBps: 1024 → 8192; metadataEntriesPerSecond: 20 → 100 | User-requested monitored limits; accepted by mailpile-transfer-20261026; pause=False. KiB/s for byte limits, entries/s for metadata. See ACTIONS.log for pressure/outcome. |
| 2026-10-27T18:01:21+00:00 | copyKiBps: 1024 → 256; verifyKiBps: 2048 → 512; reuseKiBps: 8192 → 1024; metadataEntriesPerSecond: 100 → 20 | Safety reduction; accepted by mailpile-transfer-20261026; pause=True. KiB/s for byte limits, entries/s for metadata. See ACTIONS.log for pressure/outcome. |
| 2026-10-27T18:11:41+00:00 | verifyKiBps: 512 → 1024; reuseKiBps: 1024 → 4096; metadataEntriesPerSecond: 20 → 40 | User-requested monitored limits; accepted by mailpile-transfer-20261026; pause=False. KiB/s for byte limits, entries/s for metadata. See ACTIONS.log for pressure/outcome. |
| 2026-10-27T18:15:14+00:00 | verifyKiBps: 1024 → 512; reuseKiBps: 4096 → 1024; metadataEntriesPerSecond: 40 → 20 | Safety reduction; accepted by mailpile-transfer-20261026; pause=True. KiB/s for byte limits, entries/s for metadata. See ACTIONS.log for pressure/outcome. |
| 2026-10-27 18:26 | Verification trials — outcome | 8MiB/s+100/s trial triggered guard18:01;4MiB/s+40/s trial triggered guard18:15. Automatic reductions documented above. Current revalidation1MiB/s, metadata20/s, future restore hash512KiB/s;1238MiB rechecked=12.6% of measured data total. Local PSI0/0, peer1.28/1.16; resumed. Copied data remains retained; no migration success claimed. |
| 2026-10-27T18:28:44+00:00 | reuseKiBps: 1024 → 2048 | User-requested monitored limits; accepted by mailpile-transfer-20261026; pause=False. KiB/s for byte limits, entries/s for metadata. See ACTIONS.log for pressure/outcome. |
| 2026-10-27T18:30:25+00:00 | reuseKiBps: 2048 → 3072 | User-requested monitored limits; accepted by mailpile-transfer-20261026; pause=False. KiB/s for byte limits, entries/s for metadata. See ACTIONS.log for pressure/outcome. |
| 2026-10-27 18:43 | Revalidation3072KiB/s + metadata20/s — monitored outcome | Only read cap raised after fallback:1→2→3MiB/s; metadata retained20/s to change one variable. Worker confirmed3072;1428→2731MiB rechecked. Brief peer2.01%full worker pause cleared; current local0/0, peer1.18/1.02. No writer/API alert; full verification remains pending. |

| 2026-10-27 19:03 UTC | Increase deferred; revalidation remains 3072 KiB/s, metadata 20/s | 4815 MiB rechecked (48.9%). Peer full PSI 1.99%, recent worker pauses up to 2.18%; local full 0.34%. Insufficient pressure headroom to increase safely. No writer/API alert. |
| 2026-10-27T19:04:43+00:00 | reuseKiBps: 3072 → 1024 | Safety reduction; accepted by mailpile-transfer-20261026; pause=True. KiB/s for byte limits, entries/s for metadata. See ACTIONS.log for pressure/outcome. |
