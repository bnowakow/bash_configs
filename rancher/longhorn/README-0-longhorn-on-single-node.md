# Longhorn on this K3s node

## Verified configuration

- K3s node: `proxmox3` (`10.0.0.50`), Kubernetes `v1.35.7+k3s1`.
- Longhorn chart: `v1.12.0`, reconciled by K3s' Helm Controller.
- Data engine: V1.
- Longhorn data disk: a sparse 100 GiB ZFS zvol (`rpool/longhorn`), formatted as ext4 and mounted at `/var/lib/longhorn`.
- Replica count: `1`.
- Backup target: `nfs://nas.localdomain.bnowakowski.pl:/mnt/MargokPool/archive/Backups/rancher/longhorn`.
- Existing `local-path` remains the default StorageClass; applications must explicitly request `storageClassName: longhorn`.

This is a functional **single-node** setup. It supports RWO and RWX claims, snapshots, and backups, but it is not highly available: loss of `proxmox3` also makes the only Longhorn replica unavailable. TrueNAS NFS is used for backups, not as Longhorn's replica disk.

## Prerequisites on every Longhorn node

```bash
sudo apt update
sudo apt install -y open-iscsi nfs-common
sudo systemctl enable --now iscsid
sudo modprobe dm_crypt
```

Persist `dm_crypt` in `/etc/modules-load.d/longhorn.conf`:

```text
dm_crypt
```

Longhorn V1 replica data requires an ext4 or XFS filesystem. Do not place `/var/lib/longhorn` on the ZFS root filesystem.

The data-disk mount is persisted in `/etc/fstab` using its UUID:

```fstab
UUID=<longhorn-zvol-uuid>  /var/lib/longhorn  ext4  defaults  0  2
```

Verify host prerequisites before installation:

```bash
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml /tmp/longhornctl check preflight
```

## Managed configuration

- `helmchart.yaml`: K3s Helm Controller resource; this is the applied release definition.
- `values.yaml`: the same Longhorn values in a conventional Helm values file for review/reference.

Apply a configuration change with:

```bash
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl apply -f longhorn/helmchart.yaml
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n kube-system get helmchart longhorn
```

The Helm controller then runs an upgrade job named `helm-install-longhorn` in `kube-system`.

## Health checks

```bash
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n longhorn-system get pods
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n longhorn-system get nodes.longhorn.io
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get storageclass
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n longhorn-system get backuptargets.longhorn.io
```

Expected properties:

- all Longhorn pods are `Running`;
- `proxmox3` is `READY=True` and `SCHEDULABLE=True`;
- `local-path` remains `(default)`;
- `longhorn` has `RECLAIMPOLICY=Retain` and `ALLOWVOLUMEEXPANSION=true`;
- the default backup target has `status.available: true`.

## Using Longhorn claims

Use `storageClassName: longhorn` explicitly. Example RWO claim:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
  namespace: my-app
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 10Gi
```

For shared storage, change the access mode to `ReadWriteMany`. Longhorn creates a share-manager and serves the volume to workload pods over NFS; `nfs-common` on every Kubernetes node is therefore required.

## Backups

The default backup target is configured in `defaultBackupStore.backupTarget`, not in `defaultSettings`.

Longhorn mounts the NFS target when it performs backup or restore operations. Do not add the backup target to the K3s host's `/etc/fstab`.

Before trusting a new NFS target, test from each K3s node using a temporary mount and a write/delete test. The target must be writable by Longhorn (the current TrueNAS share maps root for the K3s node).

An on-demand backup consists of a Longhorn `Snapshot` CR followed by a `Backup` CR. The supplied test manifests demonstrate this:

- `test-backup-snapshot.yaml`
- `test-backup.yaml`

Check backup progress with:

```bash
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n longhorn-system get backups.longhorn.io
```

`STATE=Completed` confirms Longhorn uploaded the backup to TrueNAS.

## Test manifests and cleanup

- `test-rwo.yaml` verified provisioning, attachment, mount, and a write through a RWO PVC.
- `test-rwx.yaml` verified two pods sharing a RWX PVC.
- `test-backup-snapshot.yaml` and `test-backup.yaml` verified a full backup to TrueNAS.

The `longhorn` StorageClass intentionally uses `Retain`. Deleting a test PVC does **not** automatically delete the associated PV or Longhorn volume. Inspect retained test resources before deleting any of them:

```bash
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n longhorn-test get pvc,pod
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get pv
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n longhorn-system get volumes.longhorn.io,backups.longhorn.io,snapshots.longhorn.io
```

## Expanding to high availability

For HA, add at least two additional Kubernetes nodes with their own dedicated ext4/XFS Longhorn disks. Install the prerequisites and mount the same data path on each storage node, then label only those nodes:

```bash
kubectl label node <node> node.longhorn.io/create-default-disk=true
```

After all nodes are healthy, create a new StorageClass with `numberOfReplicas: "3"` (or update the default for newly created volumes). Existing one-replica volumes are not automatically converted to three replicas.

## Homer migration (completed)

Homer in the `apps-homer` namespace was migrated from `local-path` to Longhorn on 2026-08-14.

- New active claim: `homer-config-longhorn` (`1Gi`, `longhorn`, RWO).
- Original rollback claim: `homer-config` (`100Gi`, `local-path`, RWO).
- The original PV `pvc-8814974b-c528-4152-a80b-10b03f85f3d7` has been changed to `Retain` and the PVC has `helm.sh/resource-policy: keep`.
- The Helm release uses `persistence.config.existingClaim: homer-config-longhorn` in `../helm-apps-modifications/homer.yaml`.
- Copied data size was approximately 992 KiB. Homer became Ready and served its homepage after the cutover.

The migration resources are kept as a repeatable reference under
`migrations/`:

- `migrations/homer/`
- `migrations/adguard-home/`

For an application migration, create and bind the target claim first, stop the application, run the copy job, then apply the Helm change that selects the target `existingClaim`. Never run the copy job while the application is writing to its source PVC.

Do not delete `homer-config` yet. If rollback is required, change `existingClaim` back to `homer-config` in the Helm values and run the same pinned Helm upgrade; verify Homer, then investigate the Longhorn volume before retrying migration.
