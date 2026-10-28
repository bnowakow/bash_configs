# Current verification controls —27October18:20UTC

## Current status — 2026-10-28T18:41:14+00:00

Migration verification100% passed, Mailpile on healthy two-replica Longhorn claims, and all52 maintenance targets restored to Fleet desired state. RESTORATION.json and RESULTS.md are the final records. CloudCasa remains a documented unchanged pre-existing Fleet template-drift exception with a Ready agent. Original Mailpile PVCs retained; no active bulk copy/verifier; no commit/push. Post-restoration peer runtime recovery and BookStack256→512Mi config expansion are documented in ACTIONS.log. Historical running/pending sections below are superseded.


User requests documentation and percentage updates every minute. Current source
measurement: data10,315,431,773 unique regular bytes,78,230entries; keys600bytes,
3entries (verification-totals.json). Staging remains intact. Old fixed20/s
inventory was checkpointed; new verified resume started18:00UTC with counters.
8MiB/s+100/s trial caused pressure pause/fallback; moderate live trial from18:11
is copy256, revalidation4096, restored hash1024KiB/s, metadata40/s. Rate monitor
PID1230382/session12970, supervisorPID1191355/session10397; source0, all other
applications quiesced. Cap changes automatically recorded in TRANSFER-CAPS.md.
All limits are now live-adjustable; do not restart verifier again just for caps.

Read VERIFICATION.md for stage percentage calculations; do not equate staged
byte completion with completed migration. New inventory progress lines provide
exact per-pass entry counts. Continue60-second user updates. Success is not yet
verified; restore Fleet-desired application state only after STATE complete and
fresh validation, through the maintenance watcher/session67109 and restore-fleet.py.
Historical snapshots below are superseded where inconsistent.

# Latest status —27October17:34UTC, validation pending

User requested documentation, verification of migration success, then application
restoration **to Fleet desired state**. Success is not yet verified. Last copy
counter9818MiB (~9.59GiB); stopped source apparent total~9.61GiB. Metadata/link
inventory checks are pending; no completed backup/restore/cutover is claimed.
Both hosts PSI0 and no writer/API alert at latest check. Keep applications stopped.

`restore-fleet.py --plan` validated52 targets read-only. It derives application
replicas and CronJob suspension from applied Fleet Helm/raw manifests, with
saved-state fallback only for supporting services outside Fleet. Mailpile is
excluded from bulk restoration. `quiesce-workloads.py restore` now delegates to
this script, requiring STATE complete and repeat final verification. Gradual
restoration and Fleet readiness are required before RESTORATION.json is written.
Maintenance watcher must continue safe controller/agent sequencing for cutover.
See RESULTS.md, MAINTENANCE.md and fleet-restoration-plan.json for current details.
Historical preparation/cap/shutdown notes below are superseded where inconsistent.

# Current status — 27 October, maintenance shutdown and active copy

**Mailpile migration is actively copying**, not waiting to start. Latest verified
copy progress1671MiB (~1.63GiB) at256KiB/s; original app replicas0. No sole-writer/
API alert file existed at maintenance verification. Source claims remain intact.

User authorized stopping everything practical, and requested documentation.
45 previously active workloads now verified desired0/current0; all47 planned
workloads (including already-zero Filebot/Mailpile) are stopped. Six CronJobs
suspended. DNS/ingress/webhooks/storage critical services remain running;
AdGuard/CoreDNS/Traefik available1 each. Peer PSI0, physical free61.14GiB while
copy in progress (start gate was met before copy). This current free figure
includes initial copied data; do not reapply the full pre-copy start forecast.

See [MAINTENANCE.md](MAINTENANCE.md) and [maintenance-plan.json](maintenance-plan.json)
for scope, counts, exact saved replicas and restoration. Full originals remain
private under /tmp/longhorn-mailpile-20261026. `quiesce-workloads.py stop` completed.
`maintenance-watch.py` is being started to restore only Fleet controller after
verified copy, then Fleet agent after new target Bundle/BundleDeployment ID,
then restore applications gradually after STATE phasecomplete. Do not restore
Fleet agent while old source bundle is still desired. Do not start duplicate
copy processes or scale Mailpile up independently. Source0 mode preserves
requested downtime on failure. Original controller PID3503504 remains active.

The sections below are historical and superseded where inconsistent.

# Current resume status — 27 October 2026

User explicitly requested resuming migration if stopped. Original app is already
replicas0 (confirmed no app Pod); no source copy has ever started. New controller
was started with `--source-stopped`, PID3503504, exec session75558. It accepts
zero source replicas, preserves requested downtime if migration fails, and
automatically resumes bounded free-block reclamation when the capacity gate
is reached. Reclamation now has an exclusive worker lock. Rates remain copy
256KiB/s, restore verification512KiB/s, pressure pause some10%/full2%.

Both APIs responded Ready but peer storage health reports were stale: failed
manager daemon, CSI listener and instance-manager/engines were absent according
to SSH. Old helper UID9c840711 was normally terminated, verified no processes,
then stale Pod record removed and fresh helper created. It cannot mount because
peer CSI socket refuses connections. Normal replacement of failed peer manager,
CSI and instance-manager was requested, logged in ACTIONS.log. Do not claim
healthy target reports alone prove live engines while peer manager is absent.

Peer pool physical free~41.35GiB, PSI0 at first check; conservative start gate
61.45GiB remains unchanged. Source0 must remain enforced. Original claims/data
are intact. Do not start duplicate coordinators or independently restart app.

The following sections preserve historical observations and are superseded
where they conflict with this current status.

# Mailpile migration preparation blocked — 2026-10-26

User authorized Mailpile migration. **No Mailpile shutdown, source data copy,
source mutation, app Fleet cutover or production replica-policy change occurred.**
Both existing HTTPS endpoints responded 302 at the final service check. Local
k3s restart count increased 60→65; both APIs repeatedly returned 503/not-ready,
connection-refused and timeout errors. A bounded five-minute observation could
not establish a two-minute stable window. Peer I/O pressure was high (some 76%,
full 52% at one sample); service restart and hardware/storage diagnosis remain
separate work. The current non-root user cannot repair host I/O/etcd through
unavailable Kubernetes APIs.

## Actual source and revised target

`apps-mailpile/mailpile` still references original `mailpile-path1` 20Gi and
`mailpile-path2` 1Gi local-path claims. Last verified app state before instability:
1/1 Ready on proxmox2-old, current chart 10.0.4, exact image
`docker.io/rroemhild/mailpile:latest@sha256:5b58d53b2f11ba6ce360006ca1f6459970b3fba8bafdeafafbf1af1d14c58172`.
The older migration recipe used chart 10.0.3 and was rejected to avoid a downgrade;
new target definitions preserve the current 10.0.4 configuration and image.

Source data has grown: **10,102,524,988 logical bytes (~9.41GiB),
8,794,885,632 allocated bytes, 75,526 entries**. Key tree 600 bytes, three entries.
The old 9Gi Longhorn data staging claim cannot fit it. The existing Fleet storage
bundle now requests **12Gi data + 256Mi keys**, total 12.25Gi per host, RWO/two
production replicas. Native Fleet apply was accepted. **The expansion's final
filesystem capacity/conditions were not verified** because the APIs failed.
Do not treat the desired 12Gi value as completed expansion evidence.

Original source claims were not deleted/reclaimed by this task. The earlier
reclamation work intentionally excluded active Mailpile. Prior 25-Oct Longhorn
staging remains unverified and must be overwritten by a fresh stopped copy,
never activated or merged based on old partial data.

## Pending helper: cleanup request NOT accepted

The created Pod `apps-mailpile/mailpile-transfer-20261026` selects proxmox2-old.
Its transfer container is Python 3.13; its keyring container uses the exact app
image but overrides its command with sleep. It mounts original data/keys
**read-only** and the two Longhorn staging claims read-write. Both commands
are idle sleeps (86400s); **no Mailpile or copy process was started in it**.

After persistent API failures, eight attempts to delete only this helper all
failed; the final runtime list also failed. **Helper deletion is unconfirmed.**
When APIs recover, inspect its state and request normal deletion to detach the
staging volumes, unless the migration owner is deliberately resuming preparation.
Do not force-detach Longhorn volumes, delete source claims or restart Mailpile
independently. The live source service was not scaled down by this task.

```sh
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n apps-mailpile get deploy,pods,pvc -o wide
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n apps-mailpile delete pod mailpile-transfer-20261026 --ignore-not-found
```

## Evidence, logs and next steps

- UTC major-action audit: `ACTIONS.log` beside this file.
- Sensitive original deployment/repository/Secret snapshots and API error output:
  `/tmp/longhorn-mailpile-20261026/`, mode 700. Never commit or paste Secret data.
- New `prepared-fleet-files.json` is unapplied app configuration, preserving the
  current chart version. `transfer-pod.json` describes the preparation helper.
- `migrate.py` has been prepared but **not executed**. Do not start it until APIs
  remain healthy, k3s counts stabilize, pools have headroom, transfer helper is
  deliberately recreated/Ready and both staging targets are healthy with two
  running host replicas and the data filesystem actually reports 12Gi.
- Copy logic is rate-limited to 4MiB/s, verifies source/target bytes with SHA256,
  sparse files, owners, modes, timestamps and links. Require a stopped sole writer.
- Quiesced native NAS backups and independent full-manifest/GnuPG-clone restore
  validation precede cutover. A disposable strict-local **one-replica** restore
  on **proxmox3 only** avoids putting a duplicate 9.4GiB scratch replica on the
  constrained peer pool. Production remains **two replicas**. Verify that actual
  scratch placement before restoring/reading data.
- Original local data remains Retain/keep until explicit future reclamation.
  No completion marker/count increase has been made; migration is incomplete.

Resume ownership belongs to this migration session. Root troubleshooting should
restore control-plane/storage health and report changes; do not independently
scale workloads, run an uncapped copy or bypass the guard/verification steps.

## User-requested throttled retry — 2026-10-26 after 19:01 CET

User requested migration again with lower bulk-copy I/O. Copy now limits to
**1MiB/s**, restored-file hashing to **2MiB/s**, copy metadata to 20 entries/s
average and metadata description to 100/s. Both operations automatically pause
if host I/O PSI some avg10 exceeds 30% or full avg10 exceeds 10%; no catch-up
burst is allowed. Production copy has still **not started**.

At retry preflight both APIs were again unready; local k3s had 70 restarts and
peer I/O PSI some 79.84%/full 68.61%. The actual `migrate.py` invocation stopped
at its first API health check, before any scale/copy/gate changes.

Read-only access to the Longhorn manager API (10.42.0.156:9500) reported five
concurrent rebuilds, 38 degraded volumes, and Mailpile data staging attached at
12Gi backend size but degraded: proxmox3 replica RW, peer replica not running.
No active rebuild was reported for that staging data volume in this snapshot.
These manager reports may lag underlying activity while Kubernetes APIs are
unavailable. Backend 12Gi does not verify mounted ext4 expansion completed.

An attempt to temporarily lower `concurrent-replica-rebuild-per-node-limit`
from 5 to 1 via Longhorn manager PUT timed out. A subsequent read still returned 5;
**the setting change is not confirmed**, and no concurrency reduction should be
claimed. The original setting response is saved at
`/tmp/mailpile-rebuild-concurrency-before.json`. Longhorn V1 does not support
the documented V2 rebuild-bandwidth QoS; no ineffective V2 setting was applied.

Peer pool free was 53,690,101,760 bytes (~50GiB) in this retry sample, leaving
only ~2.8GiB above the 20%-free planning floor. Re-measure physical allocation
(and unverified staging contents/snapshots) before any transfer; do not assume
logical filesystem free space guarantees physical pool headroom. Current source
service/storage was not changed by this retry. The staging helper's earlier
cleanup remains unconfirmed. See ACTIONS.log for timestamps and failed retry.

## Maximum-throttle controller active, 26 October evening

Controller PID 897927, exec session 3990. Current state is STATE.json; it keeps
Mailpile running until all prerequisites pass, then starts migration automatically.
Latest gate: transfer helper not Ready, peer instance-manager being recreated
after confirmed absent container/processes; normal recreation has a two-minute
backoff. Physical peer pool headroom is also below the conservative start gate.
Bounded filesystem-free-block reclamation is active (exec session 55986).
No source shutdown or bulk copy has started as of this entry. Rates: copy
256KiB/s, restored hashing512KiB/s; PSI automatic pauses. See README and ACTIONS.log.
Do not start a second coordinator or delete original claims.

## Blocker investigation, 19:04 UTC

Peer instance-manager is now Ready1/1. Both target volumes are attached; data
is healthy, keyring remains degraded because its peer replica is queued behind
serialized cluster recovery. This is not evidence of an independent keyring
copy failure: no Mailpile bulk copy has started. OpenBooks logs completed its
rebuild; healthy volume count rose10→13 during observation. Global rebuild,
backup and restore limits remain1. Do not increase concurrency to jump the queue.

Pressure peaked at some38%/full29%, then fell to some0.92%/full0.61%. Bounded
reclamation correctly paused and resumed. Last scan offset40.25GiB; peer physical
free45.24GiB, still below61.45GiB conservative start gate. No source deletion,
reserve reduction, unrelated app shutdown or live-engine restart performed.
Controller PID897927 remains active and original Mailpile remains online.
If the complete discard scan cannot reach capacity goal, review measured final
headroom before choosing a revised reserve or additional capacity; do not claim
the copy itself cannot fit (source9.41GiB, available45.24GiB).

## 27-Oct resumed workflow, latest observation07:45UTC

Peer manager/CSI/instance-manager replacements became Ready and fresh transfer
helper Ready2/2. Mounted data target verified11.71GiB total/11.69GiB free; keys
0.218GiB total. Source app/config unchanged and replicas0. Both targets later
passed health gates: controller reached waiting_for_physical_headroom. Bounded
reclamation raised free space to~50.2GiB (from41.35), below61.45GiB start gate.
Then k3s restart count154→156 and API failures interrupted readiness; controller
waiting_for_api_or_staging. No data copy/source startup/cutover occurred.

Active controller: PID3503504/session75558, --source-stopped. Bounded reclamation
uses worker lock and auto-retry on safe controller capacity checks; manual
resume session11745 may have ended or paused under pressure. Inspect ACTIONS
and STATE before any new action; do not start duplicate workflows.

## Rate adjustment, 27 October10:37UTC

User requested a modest copy-cap increase with I/O monitoring. Old supervisor
and coordinator were terminated deliberately, then only the remote fixed-rate
copy worker; helper/staging and source0 were preserved. No guard alert or
pre-cutover backup existed. Original start marker archived privately. New
supervisor PID44368/session34300 runs --source-stopped --resume-copy, initially
observing180s stability. It revalidates/reuses complete files and repairs partial
ones; full verification remains required. Rate512KiB/s is configured live in
helper /tmp/mailpile-rate.json. rate-watch.py/session69081 watches both hosts,
pauses and lowers cap256 under pressure, and records RATE.json/ACTIONS.log.
The maintenance watcher/session55240 remains active for safe cutover/restoration.
Do not start duplicate workers or revive old fixed-rate processes.

## 27-Oct13:07 cap trial

Previous monitor reduced512→256 at12:42 after local PSI15.68%some/15.05%full (peaked28.36/27.66), then retained256 after recovery. User requested another increase and documentation of every change. Current live cap768KiB/s, worker-confirmed; rate-watch.py PID430576/session99573 remains active, supports --cap and appends accepted changes to TRANSFER-CAPS.md. Short trial:3625→3712MiB verified, local PSI0/0, peer0.08/0.02, no guard alert. No copy restart occurred for this adjustment. Every future cap change must be documented and verified, including automatic reductions.

## 27-Oct13:10 cap trial

User requested another modest increase: live cap1024KiB/s (1MiB/s), worker-confirmed. New rate monitor PID439650/session76672, --cap1024. Copy progress3859MiB, no guard alert. Latest local PSI0.07/0.04, peer0.19/0.03; free60.28GiB. Short trial passed, documented in TRANSFER-CAPS.md. Safety pause/fallback256 retained; no copy restart.

## Verification-cap update —27October17:55UTC

User requested faster verification and percentage reporting. Old fixed20/s
inventory had~28% estimated completion, not exact. It was checkpointed; no
helper/PVC deletion or source restart. New supervisor session10397 runs
--source-stopped --resume-copy; rate monitor session62027 requests copy1024,
reuse8192, restored hash2048KiB/s and metadata100entries/s. Old start marker
archived privately. Both-host pressure guards and conservative reductions apply
throughout copy/restore verification. Exact per-inventory and restored-hash
progress logging added. All limits now live-adjustable; do not restart again
merely to tune metadata. Revalidation must complete before any success claim.
Fleet-desired conditional restoration watcher/session67109 remains active.

## Latest18:26UTC verification observation

Moderate4MiB/s+40/s verification trial also fell back at18:15 (automatic row in TRANSFER-CAPS). Current revalidation1024KiB/s, metadata20/s, future restore hash512KiB/s, copy256KiB/s;1238MiB rechecked=12.6% of measured data source. Source data fully staged, all production apps remain quiesced pending successful validation. Continue user verification percentages every minute. No additional worker restart needed for limit changes; current supervisor1191355, monitor1230382.

## COMPLETED 2026-10-28T16:10:02+00:00

Final runtime, Fleet, Secret, target replicas, retained sources and HTTPS checks passed. See RESULTS.md/ACTIONS.log. Source rollback PVCs remain; global throttles remain1 pending operator stability review. No commit/push performed.

## COMPLETED 2026-10-28T16:10:16+00:00

Final runtime, Fleet, Secret, target replicas, retained sources and HTTPS checks passed. See RESULTS.md/ACTIONS.log. Source rollback PVCs remain; global throttles remain1 pending operator stability review. No commit/push performed.

## COMPLETED 2026-10-28T16:48:17+00:00

Final runtime, Fleet, Secret, target replicas, retained sources and HTTPS checks passed. See RESULTS.md/ACTIONS.log. Source rollback PVCs remain; global throttles remain1 pending operator stability review. No commit/push performed.

## COMPLETED 2026-10-28T17:00:21+00:00

Final runtime, Fleet, Secret, target replicas, retained sources and HTTPS checks passed. See RESULTS.md/ACTIONS.log. Source rollback PVCs remain; global throttles remain1 pending operator stability review. No commit/push performed.

## COMPLETED 2026-10-28T17:17:16+00:00

Final runtime, Fleet, Secret, target replicas, retained sources and HTTPS checks passed. See RESULTS.md/ACTIONS.log. Source rollback PVCs remain; global throttles remain1 pending operator stability review. No commit/push performed.

## COMPLETED 2026-10-28T17:43:13+00:00

Final runtime, Fleet, Secret, target replicas, retained sources and HTTPS checks passed. See RESULTS.md/ACTIONS.log. Source rollback PVCs remain; global throttles remain1 pending operator stability review. No commit/push performed.

## COMPLETED 2026-10-28T18:28:35+00:00

Final runtime, Fleet, Secret, target replicas, retained sources and HTTPS checks passed. See RESULTS.md/ACTIONS.log. Source rollback PVCs remain; global throttles remain1 pending operator stability review. No commit/push performed.
