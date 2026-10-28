# Mailpile migration completed — 2026-10-28T16:10:16+00:00

Mailpile now runs on **12Gi data + 256Mi keys**, RWO with **two healthy replicas
on distinct hosts**. One app instance, Recreate. Current chart/image/env and
Opaque Secret data were preserved. Actual pod target mounts, Fleet deployment
IDs/Ready, both HTTPS endpoints (200 after redirects) and original source
keep/Retain protection passed final checks.

Stopped-copy logical data: **10,315,431,773 bytes**; data entries:
**78,230**. Every copied regular-file chunk was read
back and source/target SHA256 compared. Full metadata, ownership, modes,
timestamps, sparse content, symlinks and hardlink relationships were preserved.
An API readiness gap blocked the initial cutover. A fresh full original-source
hash/metadata/link recheck passed before recovered cutover. Scratch restore root
timestamps were restored to the expected manifest values; strict full restore
verification and cloned keyring checks then passed.

Quiesced native NAS backups of both targets were independently restored and
verified against the complete manifest; cloned GnuPG parsing passed using the
unchanged app image. No messages were decrypted/sent in isolated checks.
The disposable restore used one strict-local replica on proxmox3 only, to avoid
extra peer-pool pressure. Production retained two replicas. Scratch restore
claims/classes/helpers and temporary backup membership were cleaned up.

File transfer started at **256KiB/s**, then resumed with verified file reuse
and live cap adjustments at user request; hashing caps were adjusted live under
both-host pressure monitoring.
Every cap change and observed outcome is recorded in **TRANSFER-CAPS.md**.
The rate monitor watches both hosts, pauses under pressure and reduces the copy
cap to256KiB/s if necessary; ACTIONS.log records actual adjustments.
high host PSI pauses work without catch-up bursts. Native backup/restore and
rebuild concurrency were temporarily limited to one. Those global limits
remain at one for now; previous values are recorded privately for an operator
to restore after stability review. Peer manager recovery, unverified staging
replacement and bounded free-block reclamation are recorded in ACTIONS.log.
No storage finalizer was forced. Only a confirmed stale manager Pod record was
force-deleted after normal deletion failed and its daemon was absent.

Private stopped-copy manifest SHA256: `ce30de35b64360b047e198ab0688ef770f233070d8dc9fd9a6b63bea14f98986`. Its filenames and all Secret/
mail/key contents remain outside Git under `/tmp/longhorn-mailpile-20261026`.
Original local source PVCs/PVs are retained as stale rollback copies. Do not
return to them without stopping target writers and reconciling later mail.

Login, mail reading/indexing and normal fetch behavior still require user
functional testing. The underlying peer NVMe/I/O reliability problem is not
claimed repaired by this migration. See [actions](ACTIONS.log), [handoff](HANDOFF.md)
and [procedure](README.md).

## NAS backup records

- data: `backup-8aa200a6b8d94045`, created `2026-10-28T08:11:22Z`, source volume `pvc-775212e9-ac49-4664-9dd0-a239dc72bf1c`.
- keys: `backup-5a7db56e56314650`, created `2026-10-28T07:59:46Z`, source volume `pvc-dbe22a3b-837b-48c9-a83d-4b710065bc12`.
