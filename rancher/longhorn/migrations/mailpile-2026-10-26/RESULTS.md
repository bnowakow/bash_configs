# Mailpile migration — copying performed, final verification pending

Latest documented observation: **27 October2026,17:34UTC**. This supersedes the
initial preparation-blocked result. **Migration success has not been verified**;
applications must remain quiesced until the completion gate passes.

The stopped source measured10,315,431,773 apparent bytes of data plus600 bytes
of keys (~9.61GiB) on27October. The last streamed copy counter was9818MiB
(~9.59GiB), after byte-for-byte chunk verification. It is below the apparent
source total because directory metadata is included in du and progress prints
periodically. The worker remains running with no open source/target files at
the17:19 process check, consistent with full metadata/inventory checking.
No final COPY_VERIFIED/COPY_COMPLETE result or successful cutover is claimed.
Do not infer migration completion from a near100% byte count or old prepared files.

Mailpile remains scaled0 on its original local-path configuration. Original
PVCs/data remain intact. Target requests are12Gi data+256Mi keys, RWO/two
production replicas. Live transfer cap1MiB/s; the rate monitor shows both hosts
at0% PSI and no writer/API guard alert at the latest observation. Cap changes
and fallbacks are recorded in [TRANSFER-CAPS.md](TRANSFER-CAPS.md).

45 previously active workloads remain temporarily stopped; six scheduled jobs
are suspended. See [MAINTENANCE.md](MAINTENANCE.md). The user explicitly requested
restoring applications **to Fleet desired state after successful migration**.
The read-only [Fleet restoration plan](fleet-restoration-plan.json) validated
52 targets (application workloads/schedules plus supporting services).
Applications derive replicas/suspension from already-applied Fleet manifests;
services outside Fleet use their saved maintenance state. Mailpile is excluded
from bulk restoration because its own migration must validate its target instance.

`quiesce-workloads.py restore` now delegates to `restore-fleet.py`. Actual
restoration requires STATE phasecomplete and repeats final runtime, mount,
replica, backup, Fleet and endpoint checks before changing other workloads.
Restoration is gradual, databases first, with pressure/rollout checks and final
Fleet readiness verification. RESTORATION.json is written only after that succeeds.
The maintenance watcher handles Fleet controller/agent ordering for cutover;
it must not reactivate the old Mailpile source bundle.

Remaining: complete copy/inventory verification, fresh native NAS backups,
independent full-manifest/keyring restore verification, safe Fleet cutover and
final runtime checks; then restore applications and verify Fleet convergence.
The normal finalizer will replace this pending report only after those
migration checks actually pass. No migration completion count is added yet.
