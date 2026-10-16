# Longhorn backup and restore

## Native NAS backup

The live `nas-daily-backup` RecurringJob is defined in
`../fleet/infrastructure/longhorn-backups/recurring-job.yaml`.
It runs at `0 1 * * *` (01:00 in the Kubernetes controller timezone;
the generated CronJob has no explicit `timeZone`). It retains the newest
14 backups per selected volume, runs one volume at a time, and performs a
full upload every seven incremental backups. Unchanged volumes do not produce
a new backup on every run. Detached volumes are currently skipped.

Target:
`nfs://nas.localdomain.bnowakowski.pl:/mnt/MargokPool/archive/Backups/rancher/longhorn`.
Backup and recovery use your NAS and Longhorn without the CloudCasa service.
The NAS must remain available and its backup data must be preserved.

Opt each migrated application PVC into this schedule:

```yaml
metadata:
  labels:
    recurring-job.longhorn.io/source: enabled
    recurring-job-group.longhorn.io/nas-backup: enabled
```

These labels are present on `apps-homer-test/homer-test-config-longhorn-rwx`
both live and in its Fleet manifest. Restore test volumes are not selected.
The Fleet files have not been committed or pushed by this procedure.

Check or run the actual scheduled job:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl -n longhorn-system get recurringjob nas-daily-backup
kubectl -n longhorn-system get cronjob nas-daily-backup
kubectl -n longhorn-system create job --from=cronjob/nas-daily-backup YOUR_UNIQUE_JOB_NAME
kubectl -n longhorn-system logs job/YOUR_UNIQUE_JOB_NAME
kubectl -n longhorn-system get backupvolumes.longhorn.io
```

## Verification on 2026-10-08

Native job `nas-backup-test-20261008` completed successfully and created
`backup-dbc8be0668184c97` for
`pvc-3bc8aad0-e2c6-41d9-9923-1bdc76670b8c`.
The backup was restored using a separate StorageClass with `fromBackup`
pointing to that NAS backup URL, a new 10Mi RWX PVC, and a Homer pod.

- Namespace: `apps-homer-test-native-restore`
- PVC: `homer-restored`
- Restored volume: `pvc-d229fc43-effb-4944-92ef-5e3a6b6783cc`
- StorageClass: `homer-native-restore-20261008` (Retain)
- Pod: `restore-check`, assets mounted read-only
- All 43 source regular files matched their SHA-256 checksums.
- HTTP requests to `/` and `/assets/config.yml` succeeded.
- Restore manifest: `/tmp/homer-native-restore.json` (temporary).
- Source checksums: `/tmp/homer-test-source-sha256.txt` (temporary).

CloudCasa copy backup `6ac7e1d4375b3c53c0ec1e81` completed successfully.
The agent reported a live-PVC copy, about 897 KB.
CloudCasa restore `6ac7e2efbb44c249233a46db` completed with zero errors and
two warnings. It restored into the **existing** `apps-homer-test` PVC with
resource update policy; it did not create an isolated replacement volume.
Both counted warnings were rejected patches attempting to clear `spec.nodeName`
on the two existing running Homer pods. The data mover successfully wrote
43 files (897,167 bytes); these pod metadata warnings did not prevent copying.
Afterward all 43 checksums matched and Homer served both HTTP paths.
The native schedule labels survived the restore.
The PVC request was subsequently aligned from 1273Ki to its already allocated
10Mi capacity, addressing CloudCasa's separate backup capacity warning.

CloudCasa schedule inclusion/frequency/retention and a restore to a new
namespace still require confirmation from the CloudCasa service UI.
For the isolated test, restore only the PVC and map `apps-homer-test` to
`apps-homer-test-cloudcasa-restore`, retaining storage class `longhorn`.
Keep workloads excluded and use a separate read-only verification pod.

Run the reusable verification script against a pod mounting the recovered
PVC at `/www/assets`:

```bash
bash longhorn/verify-homer-restore.sh NAMESPACE POD CONTAINER /tmp/homer-test-source-sha256.txt
```

The source checksum list excludes filesystem `lost+found`. This verifies
Homer's regular files and HTTP startup, not database application consistency.
For database apps, include their database backup/quiesce procedure before
copying volumes.

The test namespace, pod, PVC, volume, and StorageClass remain for inspection.
Deleting a PVC with Retain does not remove its Longhorn data automatically;
review the associated PV/volume before eventual cleanup.

References:
- https://longhorn.io/docs/1.13.0/snapshots-and-backups/scheduling-backups-and-snapshots/
- https://longhorn.io/docs/1.13.0/snapshots-and-backups/backup-and-restore/restore-from-a-backup/
- https://docs.cloudcasa.io/help/reference-pv-types.html
