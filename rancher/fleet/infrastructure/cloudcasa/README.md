# CloudCasa backup change and proxmox3 handoff

## Change recorded 29 October 2026

After migrating application PVCs from local-path to Longhorn, the user changed
the CloudCasa backup definition to read Longhorn PVCs directly. Screenshots
taken at approximately 16:47 Europe/Warsaw show the configuration below.
These screenshots document the selected settings. The subsequent proxmox3
report below confirms that the new run uses `LIVE_FROM_PVC`.

This is a CloudCasa UI configuration change, not a Fleet manifest change.
No cluster changes, new backup run, or restore verification were performed
as part of documenting this handoff.

| Setting | Previous | New |
| --- | --- | --- |
| Protection mode | Copy to backup storage | Unchanged |
| Configure backup method by storage class | Enabled | Unchanged |
| `longhorn` | Read data from snapshot | Read data from PVC |
| `longhorn-rwo-2replicas` | Read data from snapshot | Read data from PVC |
| `longhorn-static` | Read data from snapshot | Read data from PVC |
| `local-path` | Read data from PVC | Unchanged |
| `homer-native-restore-20261008` | Skip | Unchanged |

The migrated application claims in Fleet use `longhorn-rwo-2replicas`;
see `../longhorn-pilot-storage/storageclass.yaml` and the other Longhorn
storage bundles under `infrastructure/`.

Other settings shown in the new screenshots remain:

- Preserve snapshots after backup: off.
- Compression: inherit from cluster preferences.
- Concurrent PVCs: 2 (default).
- Concurrent files per PVC: 12 (default).
- Max transfer rate per PV: unlimited.
- Data mover pod timeout: 15 minutes.
- Data mover memory limit: not set in the UI (effective default unverified).
- Configure data mover user: off.
- Exclude unattached PVCs: off.
- Storage class mapping for PV snapshots mounted during backup: off.
- Configure data mover node affinity: off.
- VM changed block tracking: off.
- CSI snapshot timeout: 10 minutes.

## Previous run and evidence

Job ID: `6ae2ee307ccf37a380eee3c4`.

Source archive on the user's Mac:
`/Users/sup/Downloads/cloudcasa-k8s_copy-6ae2ee307ccf37a380eee3c4.zip`.
This archive is not included in the repository and may need transferring
separately to proxmox3 if the old logs are required.

The archive contains gzipped copy-agent, snapshot-agent and snapshot-helper
logs. The snapshot helper recorded the three Longhorn classes as `SNAPSHOT`
and local-path as `LIVE_FROM_PVC`. It repeatedly waited 10 minutes for a
VolumeSnapshot to bind to VolumeSnapshotContent, then failed with:

```text
Phase1 watch failed for VolumeSnapshot apps-adguard-home/cc-adguard-home-config-longhorn-rwo-pnqww
timed out or failed watching VolumeSnapshot ... for VSC binding: timed out waiting for the condition
```

The first shown AdGuard Home wait ran from 06:56:58 to 07:06:58 UTC.
Similar failures followed for Audiobookshelf, Authelia and other volumes.
The agent reported `PartiallyFailed`, with 287 errors and 11 warnings.
Those totals include follow-on errors; they do not establish 287 independent
storage failures.

The observed failure is snapshot binding, before data mover mounting/copying.
Its root cause was not established. Raising the data mover pod timeout does
not target this observed phase. Reading directly from PVC bypasses this
snapshot path; it does not demonstrate that CSI snapshots are repaired.

CloudCasa documents this selection as the replacement for its former
"Copy from live Longhorn PVs" option:
https://docs.cloudcasa.io/help/relnotes-07-2024.html

Longhorn-specific guidance and application consistency considerations:
https://docs.cloudcasa.io/help/reference-pv-types.html

## Follow-up run: progress reported 29 October 2026

Job ID: `6ae36a161aeff6e71701c6df`.

Evidence source: the user pasted a Codex report from proxmox3 analyzing saved
logs. The new run's underlying logs were not independently inspected in this
chat. At 15:55 UTC / 16:55 Europe/Warsaw, that report recorded:

- The job uses `LIVE_FROM_PVC`, confirming the configuration change took effect.
- Eight PVCs completed successfully, including volumes for Zabbix PostgreSQL,
  Sonarr, DuckDNS, YouTubeDL, Bindery and Jellyseerr. The report did not list
  all eight PVC names.
- Mailpile data was actively copying: approximately 7.37 GB read out of
  11.31 GB estimated (65%), with 2.39 GB transferred.
- Mailpile's second PVC was active, without byte counters yet.
- Setup logged `repository already initialized` errors, but successful copies
  followed. These messages did not stop the observed copying; their effect on
  the final job status remains unverified.
- The capture ended while Mailpile was active. Overall completion, final
  error/warning totals and restore usability were not confirmed.

This is clear progress compared with job `6ae2ee307ccf37a380eee3c4`, which
repeatedly timed out binding snapshots and ended `PartiallyFailed`. Successful
PVC copies show that direct reads bypassed the previous blocker for those
volumes. They do not establish complete backup coverage, application
consistency, or a repair of the CSI snapshot mechanism.

Next evidence needed: final job status and per-PVC results, accounting for
every selected claim, followed by a representative isolated restore test.

## Continue analyzing the run on proxmox3

1. Record the new job ID, start/end times, final state, warnings and errors.
   Verify the saved job definition actually uses live PVC reads for all three
   Longhorn classes. If logged, expect `LIVE_FROM_PVC` instead of `SNAPSHOT`.
2. Compare the selected PVC inventory with the backed-up PVC inventory,
   including migrated `*-longhorn-rwo` claims. Check per-volume bytes and
   completion status; a successful resource backup alone is insufficient.
   Account explicitly for the intentionally skipped restore storage class.
3. Confirm the previous snapshot-binding timeouts are absent for the selected
   Longhorn classes. If they remain, first check the effective definition and
   whether the run used another job or an older saved configuration.
4. For any new failures, collect CloudCasa agent/helper/data mover logs,
   relevant pod status and events, PVC/PV details, node placement and Longhorn
   volume health. Distinguish scheduling, attachment/mount, permissions,
   file-read, memory and backup-target/network failures from snapshot errors.
5. Observe node I/O pressure, k3s/API health and Longhorn health during copying.
   This cluster has a documented history of severe I/O pressure during PVC
   migrations. Current backup settings still allow unlimited transfer speed;
   do not assume that their safety or performance has been validated.
6. Assess application consistency: live reads can capture changing database
   files. Check existing hooks/native database backups before claiming a
   consistent application backup. Validate a representative restore into an
   isolated destination before relying on the new backups.

Start with read-only diagnosis. Any PVC migration must follow the standing
cluster-wide application shutdown procedure in `rancher/AGENTS.md` and
`rancher/longhorn/README-5-pvc-migration-maintenance.md`.

## Screenshot evidence

Original settings: `Screenshot 2026-10-29 at 16.43.21.png` and
`Screenshot 2026-10-29 at 16.43.40.png`.

Updated selections: `Screenshot 2026-10-29 at 16.47.18.png` and
`Screenshot 2026-10-29 at 16.47.27.png`.

All four were supplied by the user from their Mac Dropbox screenshot folder;
the images are not included in this repository.
