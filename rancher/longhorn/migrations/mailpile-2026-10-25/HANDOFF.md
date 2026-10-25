# Mailpile migration handoff: blocked, original service restored

## Current authoritative state

**Mailpile is NOT migrated.** It is back at one desired/available replica using
original local-path claims `mailpile-path1` and `mailpile-path2`. Original HTTPS
returned 200 after recovery. Original claims have Helm keep annotations and PVs
Retain protection; source data was not overwritten or deleted. Existing 26
migrated apps/36 production Longhorn claims/18.75Gi remain the completion totals.
No inventory completion marker was added for Mailpile. No Git commit/push.

The interrupted copy Job was deleted and temporary measure/image-cache/evidence
inspection resources were cleaned up. The evidence PVC was removed after its
private manifest was confirmed **not created**. No quiesced Mailpile backup or
isolated restore was started; the coordinator never passed the copy stage.

Two new target claims remain as **unverified staging**, not live app state:
- `apps-mailpile/mailpile-path1-longhorn-rwo`, 9Gi, volume
  `pvc-89347e7b-5df2-40a3-bb16-a98391908f6a`.
- `apps-mailpile/mailpile-path2-longhorn-rwo`, 256Mi, volume
  `pvc-dbe22a3b-837b-48c9-a83d-4b710065bc12`.

They belong to Fleet `longhorn-mailpile-storage` and reserve **9.25Gi per host**.
They may contain partial derived mail/key data; do not activate them. Detached
volume actualSize=0/unknown is NOT proof they are empty. Original source claims
are distinct names without the `-longhorn-rwo` suffix. Source app Fleet values
were never changed; proposed app definitions remain in prepared-fleet-files.json.

## Incident and recovery

Preflight API readiness passed, k3s was active at NRestarts=8 and source Mailpile
was Ready. Targets were Bound; only storage bundle applied. The writer was
stopped normally and copy Job `mailpile-longhorn-copy-20261025` created.
During the bulk copy the API again alternated connection refused/unexpected EOF/
ServiceUnavailable. The coordinator refused cutover. Its EXIT recovery attempted
source replicas=1 but initially could not reach the API.

Recovery then used either API endpoint with bounded requests; a scale to one
succeeded. Source mounts/availability and HTTPS were verified. The copy Job was
deleted to halt remaining work. No target app references were installed.
Local k3s NRestarts rose **8 -> 10 -> 15**, last observed active timestamp
**2026-10-25 09:15:40 CET**. Service failures continued after the initial copy
outage; transient idle recovery alone should not be treated as proven load-safe
etcd/storage health.

Saved Job status `/tmp/mailpile-interrupted-copy-job.json` reports:
- startTime **2026-10-25T07:37:25Z**;
- failed=1, BackoffLimitExceeded, failure condition timestamp
  **2026-10-25T08:15:57Z**.
The failed container log/exit cause was not captured before Job deletion;
do not assume its exact cause from the API errors. The final manifest did not
exist, so the complete stopped-copy verification did not finish successfully.
No checksum/restore success may be claimed.

A previous root investigation of similar outages is preserved in
`../sonarr-ytdl-adguard-2026-10-24/HANDOFF.md`: severe etcd WAL fdatasync stalls,
two voting members requiring both for quorum, root ZFS-backed storage, and
leader-election failures. This new failure recurred during heavy copy work,
but the underlying cause and the copy container's failure still need root
journal/kernel/cgroup/storage evidence. Do not blindly reset etcd or change
firewall rules. Prioritize stable control-plane/storage behavior under intended
I/O before another bulk migration attempt. Current session lacks passwordless
sudo/system journal access; use a sudo-enabled session for host diagnostics.

Relevant hosts/APIs: proxmox3 10.0.0.50 (local 127.0.0.1:6443) and proxmox2-old
10.0.0.72:6443. Source Mailpile and copy ran on proxmox2-old. The .72 endpoint
was usable for recovery when local API was unavailable. SSH as sup with the
existing key/known_hosts works to .72; sudo there requires a password.

## Prepared work and resume requirements

Original definitions/metadata: `/tmp/longhorn-mailpile-originals/`.
Snapshots/evidence: `/tmp/mailpile-preflight.json`,
`/tmp/mailpile-interrupted-copy-job.json`, `/tmp/mailpile-recovery-state.json`,
`/tmp/mailpile-blocked-state.json`, `/tmp/mailpile-final-source.json`,
`/tmp/mailpile-blocked-longhorn.json`, `/tmp/mailpile-final-space.json`.

Files in this directory:
- prepared-fleet-files.json: final app target references, singleton/Recreate.
- copy-job.json, manifest-check.py: complete copy with content/permissions/link
  verification, private per-file evidence on a temporary local-path PVC.
- check-keyring.py: Python 2/GnuPG 1.4.23 metadata parse in a disposable clone.
- prepare-restore.py: two fresh native backup restores and full manifest match.
- migrate.sh: intended stop/copy/quiesced-backup/restore/activate sequence.

Fresh measurement was **6070158848 allocated / 6921275612 apparent data bytes**,
43443 entries; keys **5632 allocated / 600 apparent bytes**, three entries.
Targets 9Gi + 256Mi fit the measured logical size plus buffer. The image remains
`docker.io/rroemhild/mailpile:latest@sha256:5b58d53b2f11ba6ce360006ca1f6459970b3fba8bafdeafafbf1af1d14c58172`.
Chart 10.0.3, source root mounts `/root/.local/share/Mailpile` and `/root/.gnupg`,
root UID/GID 0, original pod fsGroup 568. Both HTTPS hosts had baseline 200.

Copy/restore fixtures passed sparse-file, hardlink, symlink, metadata checks and
corruption rejection. Render checks normalized API defaults/order and confirmed
unchanged image/env/mount paths. Actual large-copy validation did NOT pass.

Before retry: re-check original app/source health and current sizes. Diagnose
host storage/etcd stability and the failed-copy cause; use appropriately bounded
I/O rather than repeating uncontrolled load. Recreate the cleaned evidence PVC
and tooling from `/tmp/mailpile-tooling.json` and measurement manifest if needed.
Unverified target contents must be safely cleaned/resynchronized while no app
uses them; the current script is not an incremental resume and should not be
blindly rerun over a partial/stale target. Keep all originals intact.

The intended safe procedure remains: stopped complete copy -> verify every
file/permission/link -> hold targets attached read-only -> native quiesced NAS
backup -> isolate restore and compare all bytes to the stopped-copy manifest ->
activate app via Fleet -> validate endpoints/replicas -> cleanup scratch. Do not
start a second Mailpile instance against mail/accounts, send test mail, print
keys/mail contents or apply target references before checks complete.

Read fleet/AGENTS.md; use the Fleet-native pilot apply helper, preserve GitRepo
labels/targeting, and do not commit/push unless requested. Do not re-migrate the
already completed apps or overwrite unrelated changes.
