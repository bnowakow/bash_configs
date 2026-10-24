# Calibre group, Profilarr and Radarr migration results — 2026-10-24

Completed and applied through Fleet: Calibre, Calibre Web, Kavita, Profilarr and
Radarr. All five have one available application replica, Recreate strategy and
their new target mounts. All six RWO volumes use `longhorn-rwo-2replicas`, with
two healthy storage replicas on distinct hosts (proxmox2-old and proxmox3).
All seven changed Fleet bundles report 1/1 BundleDeployments ready, including
the new storage bundle and updated cover-maintenance bundle.

| Source retained | New Longhorn claim | Request | Regular files SHA256 verified | SQLite checks |
| --- | --- | ---: | ---: | --- |
| calibre-config | calibre-config-longhorn-rwo | 256Mi | 131 | Three ChapterSummarizer plugin/history databases: OK |
| calibre-library | calibre-library-longhorn-rwo | 1Gi | 38 | metadata.db + .calnotes/notes.db: OK |
| calibre-web-config | calibre-web-config-longhorn-rwo | 256Mi | 35 | app.db + gdrive.db: OK |
| kavita-config | kavita-config-longhorn-rwo | 256Mi | 271 | kavita.db: OK |
| profilarr-config | profilarr-config-longhorn-rwo | 1Gi | 2426 | data/profilarr.db: OK |
| radarr-config | radarr-config-longhorn-rwo | 1Gi | 2180 | radarr.db + logs.db: OK |

All copied regular files matched SHA256; **eleven SQLite databases** passed
quick_check on targets before cutover. Complete trees and WAL/SHM sidecars were
preserved with filesystem metadata. All old application pods were gone before
copying; original source mounts remained read-only. Original PVCs remain Bound
with Helm keep annotations, and original PVs use Retain. They are historical
rollback copies, not live data. No source database repair/checkpoint was done.

Fresh read-only measurements before shutdown:

| Source claim | Allocated bytes | Apparent bytes |
| --- | ---: | ---: |
| calibre-config | 12334080 | 20412327 |
| calibre-library | 243018752 | 244005746 |
| calibre-web-config | 1634304 | 1708786 |
| kavita-config | 49332736 | 57570824 |
| profilarr-config | 483140096 | 503943088 |
| radarr-config | 583802368 | 635804347 |

## Coordinated Calibre move

Preflight found three apps and the cover-maintenance CronJob as library
consumers; existing maintenance Jobs had completed. No active CloudCasa helper/
kubemover was present. Maintenance was suspended, all three apps stopped, and
all source consumers rechecked absent before copying the four claims together.
The desktop required a second 55-second shutdown wait; copying did not begin
until its pod was gone. Pre-cutover failure handling restores original replica
counts and CronJob suspension state without installing target references.

Calibre, Calibre Web, Kavita and maintenance explicitly share
`kubernetes.io/hostname: proxmox2-old`. Calibre retains writable `/library`, while
Calibre Web and Kavita retain read-only library mounts. Maintenance extraction
writes the library with the desktop stopped; thumbnails write web-config as
before. This is single-node application placement with replicated storage, not
application HA or multi-writer RWX. Future node moves require coordinated
shutdown/detachment and selector changes for all consumers.

The maintenance Job template now references the new library/web-config claims
and was verified before restoring its normal 03:00 Europe/Warsaw schedule.
Fleet's resume update initially remained WaitApplied; after verifying all new
mounts and app rollouts, the live suspend flag was patched false to match the
Fleet manifest. Fleet subsequently applied the matching deployment ID and
reports Ready/nonModified. Live suspension is false. No maintenance import/cover
write Job was manually triggered for this migration.

`calibre-storage` still owns the retained original library/web-config claims;
new targets belong to `longhorn-calibre-arr-storage`. All app/chart image
versions, NAS media mounts, credentials and unrelated configuration are unchanged.

## Profilarr, Radarr and endpoint checks

Profilarr's chart-owned PVC was disabled with `persistentVolumeClaims: null`;
the storage bundle owns the target. The custom chart omits Deployment replicas,
so its single replica was explicitly restored only after the new mount arrived.
Radarr uses TrueCharts existingClaim. Both target rollouts completed.

- Eight certificate-verified HTTPS checks returned 200: both configured suffixes
  for Calibre, Calibre Web, Kavita and Profilarr roots.
- Four Radarr HTTPS checks returned 200: `/ping` and `/login` on both suffixes.
- Radarr root returns an absolute HTTP login redirect; a non-HSTS urllib client
  followed it to the HTTP entrypoint and received 404. The HTTPS login route
  works, and the response sets Strict-Transport-Security. The copied UrlBase is
  unchanged/empty. No unrelated reverse-proxy/auth settings were changed.
- Recent 150-line logs for each app had no SQLite corrupt/not-a-database,
  malformed/locked/read-only database or permission-denied messages.

Authenticated user actions, Calibre desktop WebSocket sessions, book imports,
Calibre Web downloads, Kavita scans and Radarr/Profilarr integration actions
were not exercised. Please validate those normal workflows before retiring any
rollback copies. HTTP status/readiness alone is not end-to-end user validation.

## NAS backups and isolated restore

Native Job `longhorn-system/calibre-arr-nas-backup-20261024` completed at
**2026-10-24 19:45:25 UTC**. All six migrated volume backups report Completed:

| Claim | Longhorn volume | Backup |
| --- | --- | --- |
| calibre-config-longhorn-rwo | pvc-a2d72b09-d038-421e-a242-2dfa89e197ee | backup-6c868c3e64eb4781 |
| calibre-library-longhorn-rwo | pvc-20f47620-dd54-4c1a-a8e3-edde47ed12a0 | backup-3338a46a22eb42ca |
| calibre-web-config-longhorn-rwo | pvc-d9801cb3-d88c-4313-af68-90eb51ed52fd | backup-1756a29caf5d4cbc |
| kavita-config-longhorn-rwo | pvc-b35b40d7-2900-4e97-914e-ef4de27ac0f8 | backup-75381575f64a4ccc |
| profilarr-config-longhorn-rwo | pvc-35563078-ffd7-423b-8474-511b4378d247 | backup-b8092e873fec477a |
| radarr-config-longhorn-rwo | pvc-cc5816ae-faa7-4d82-a8e6-401a8ce2379f | backup-96283b47f3da4d3f |

All four Calibre backups were restored to isolated scratch volumes (three 256Mi
configs and one 1Gi library). Eight restored SQLite files passed quick_check,
including shared library/notes, Calibre Web accounts/config, Kavita and plugin
history. The check launched only Python; it did not start apps or maintenance
and mounted no production claims. Scratch PVCs/Delete-policy StorageClasses,
the restore Job and measurement Jobs were removed afterward. Copy Jobs remain
as execution evidence. Profilarr and Radarr backups were not individually
restore-tested.

Targets join the existing daily `nas-backup` group, retaining 14 backups. These
are live, separately captured volume snapshots rather than atomic/quiesced
cross-volume backups; this representative four-volume restore passed, while
future consistency-sensitive operations still need application coordination.

## Capacity and records

This batch adds **3.75Gi per host / 7.5Gi aggregate nominal replica capacity**.
Migrated production apps now total **23 apps, 30 RWO claims, 12Gi requested**
(**24Gi nominal aggregate replicas**). Remaining conservative requests total
**64Gi across 15 source claims/seven apps**. Nominal remaining budgets are about
**58.36Gi on proxmox2-old / 85.85Gi on proxmox3**. Physical allocation, snapshots
and free-space margins are separate. No disk enlargement or default class change.

Updated the [current summary](../../current-app-storage-summary-2026-10-24.md),
[assessment](../../fleet-storage-migration-assessment-2026-10-24.md), CSV completion
markers, [remaining size ranks](../../remaining-migration-priority-2026-10-24.md)
and affected app/maintenance READMEs. Original measurements remain historical.
Render invariants checked unchanged images/NFS, no chart-owned target PVCs,
shared mount modes, singleton/Recreate and required placement. Bash syntax,
ShellCheck and whitespace checks pass. The copy/check program is reused from
the multi-claim/WAL-tested preceding batch. No commit or push was made.
See [execution and rollback procedure](README.md).
