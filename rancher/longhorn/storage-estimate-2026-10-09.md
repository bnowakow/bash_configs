# Full local PVC migration space estimate — 2026-10-09

Read-only inventory of all 36 bound local-path PVCs, including the manually
provisioned hostPath volumes. Per-volume measurements are in
`local-pvc-usage-2026-10-09.csv`. Measurements used `du -s -B1` and
`du -s -B1 --apparent-size` on each PV's owning node over root SSH.
Live application writes can change values during measurement.
External NAS media mounts and existing Longhorn test volumes are excluded.

## Current data

- Allocated directory usage: 30.890 GiB.
- Apparent directory usage: 47.586 GiB.
- Declared local PV capacities: 2,369.001 GiB (2.314 TiB).
- Mail data: 19.471 GiB allocated / 22.238 GiB apparent; PVC capacity 10 GiB.
- Zabbix PostgreSQL: 5.520 GiB allocated / 13.421 GiB apparent; capacity 5 GiB.
- Mailpile path1: 2.443 / 2.682 GiB.
- AdGuard data: 1.501 / 5.929 GiB.

Allocated and apparent sizes differ due to allocation, sparse files and/or
filesystem storage behavior. These do not directly predict Longhorn's physical
block allocation. For planning use 31–48 GiB as the current-data baseline,
then allow extra for ext4 metadata, migration handling of sparse files, growth,
deleted blocks, snapshot history and rebuilding. This range is not a bound.

## Cluster disks and replica policy

| Node | Longhorn disk total GiB | Free GiB | Reserved GiB | Remaining logical scheduling budget GiB | Free above 25% disk threshold GiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| proxmox2-old | 78.19 | 78.03 | 7.82 | 70.35 | 58.48 |
| proxmox3 | 97.87 | 97.75 | 0 | 97.85 | 73.29 |

Storage overprovisioning is 100% (no logical overprovisioning). The minimum
available percentage is 25%; it constrains new replica scheduling, rather
than enforcing a permanent free-space quota on application writes.

The regular `longhorn` StorageClass specifies ONE replica, despite the manager
default of two and homer-test currently using two. A migration must deliberately
choose replica count. Current-data-only estimates:

- One replica: 31–48 GiB aggregate.
- Two replicas: 62–95 GiB aggregate, approximately 31–48 GiB per node.
- Retaining current volume capacities: about 2.31 TiB for one replica or
  4.63 TiB for two, which cannot schedule on the existing disks.

With two replicas on the two nodes, the sum of chosen nominal volume sizes must
fit the smaller node's approximately 70.35 GiB scheduling budget. As an
illustration, sizing every PVC to 1.5 times apparent usage and rounding up to
whole power-of-two GiB, minimum 1 GiB, totals 153 GiB per node; even those
sizes require larger disks. This is a sizing illustration, not a migration plan.
For two replicas, a starting disk allocation of about 200 GiB PER NODE gives
much more practical room for nominal capacities and growth than 78/98 GiB.
Validate app-specific growth and snapshot churn before deciding final sizes.

## NAS retention estimate

The current job runs daily, retains 14 backups per volume, concurrency 1,
and performs a full upload after seven incremental backups. Backup data is
shared between recovery points for the same volume; a periodic full upload
overwrites existing blocks rather than storing an independent additional full
copy. Replica count does not multiply NAS backup space.

Illustrative model: `B + 13 × C`, where B is the current block-data baseline
and C is new retained block content between successive recovery points.
Assume no volume growth, roughly stable B, 14 changed recovery points, and
no compression benefit. Filesystem/block rounding and metadata add overhead.

| New unique block content per interval | NAS GiB using measured 30.89–47.59 GiB baseline |
| --- | ---: |
| None | 31–48 |
| 1% of baseline | 35–54 |
| 5% | 51–79 |
| 10% | 71–109 |
| Entire baseline changes uniquely each interval | 432–666 |

These are scenarios, not measured change rates. Database WAL, logs and
rewrites can cause substantial churn even when directory size stays stable.
Budget 100–150 GiB initially on the NAS and monitor actual block growth;
high churn or application growth can exceed this. The mounted NAS pool reports
approximately 8.7 TiB available, shared with its other data. NAS filesystem
snapshots may keep deleted Longhorn backup blocks beyond Longhorn retention.
CloudCasa backup consumption is additional and not included here.

Auto cleanup of recurring backup snapshots and system-generated snapshots is
enabled. Local snapshot storage therefore is not 14 full data copies. Historical
blocks, temporary snapshots and other snapshot creators can still increase
replica usage; no daily-write rate was measured by this inventory.

The backup job only selects volumes in `nas-backup`; merely applying its
manifest does not enroll all PVCs. Add the group and source labels in each
migrated PVC manifest. No cluster configuration was changed by this estimate.

Sources:
- https://longhorn.io/docs/1.13.0/snapshots-and-backups/backup-and-restore/create-a-backup/
- https://longhorn.io/docs/1.13.0/snapshots-and-backups/scheduling-backups-and-snapshots/
- https://longhorn.io/kb/space-consumption-guideline/
- https://raw.githubusercontent.com/longhorn/longhorn-manager/v1.13.0/app/recurringjob/volume.go
