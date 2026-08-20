# Longhorn on a second K3s node

This guide prepares a second node to host Longhorn V1 replicas.

The current cluster configuration uses:

- Longhorn V1;
- `/var/lib/longhorn` as the default disk path;
- ext4-backed Longhorn disks;
- `open-iscsi` for volume attachment;
- `nfs-common` for backups and RWX volumes;
- `node.longhorn.io/create-default-disk=true` to opt a node into default-disk creation.

## Storage layout

ZFS itself must not be used directly as the Longhorn replica filesystem. The supported layout is:

```text
ZFS pool -> ZFS zvol -> ext4 -> /var/lib/longhorn
```

If K3s runs directly on the node, create or use a dedicated zvol and mount its ext4 filesystem at `/var/lib/longhorn`.

If K3s runs inside a VM, create the zvol on the Proxmox host, attach it to the VM as a disk, and perform the formatting and mounting inside the VM. Do not mount the same filesystem on both the Proxmox host and the VM.

For the existing second-node preparation, the disk is already mounted as:

```text
/dev/zd240 -> ext4 -> /var/lib/longhorn
```

Do not format or recreate this device.

Check the mount and capacity:

```bash
findmnt /var/lib/longhorn
df -h /var/lib/longhorn
```

The mount must be persistent in `/etc/fstab`, preferably by filesystem UUID:

```fstab
UUID=<longhorn-filesystem-uuid>  /var/lib/longhorn  ext4  defaults  0  2
```

For example:

```fstab
UUID=18ac8246-d16c-4dfd-873b-a53bc0348957  /var/lib/longhorn  ext4  defaults  0  2
```

Also check the backing pool before allocating a sparse zvol:

```bash
sudo zpool list
sudo zfs list -t volume
```

A sparse zvol advertises its full virtual size but consumes ZFS pool space as data is written. Leave sufficient free space in the pool.

## Install host prerequisites

On Debian or Ubuntu:

```bash
sudo apt update
sudo apt install -y open-iscsi nfs-common cryptsetup dmsetup
sudo systemctl enable --now iscsid
```

Load the required kernel modules:

```bash
sudo modprobe iscsi_tcp
sudo modprobe dm_crypt
```

Persist them across reboots:

```bash
sudo tee /etc/modules-load.d/longhorn.conf >/dev/null <<'EOF'
iscsi_tcp
dm_crypt
EOF
```

Verify the prerequisites:

```bash
systemctl is-active iscsid
lsmod | grep -E 'iscsi_tcp|dm_crypt'
command -v iscsiadm
command -v mount.nfs
```

## Join the K3s cluster

Join the node to the existing K3s cluster using the same K3s version as the cluster. Use the cluster's server URL and node token. Join as an `agent` for a worker/storage-only node, or as a `server` when an additional control-plane node is intended.

Do not store or commit the node token in this repository.

After the installation, confirm that Kubernetes sees the node:

```bash
kubectl get nodes -o wide
```

## Enable the Longhorn disk

Label the node to request Longhorn's default disk:

```bash
kubectl label node <node-name> node.longhorn.io/create-default-disk=true
```

If the label already exists, use `--overwrite` only when deliberately correcting it:

```bash
kubectl label node <node-name> node.longhorn.io/create-default-disk=true --overwrite
```

Run the Longhorn preflight check from a host with access to the cluster kubeconfig:

```bash
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml \
  /tmp/longhornctl check preflight
```

## Verify Longhorn

```bash
kubectl -n longhorn-system get pods -o wide
kubectl -n longhorn-system get nodes.longhorn.io
```

The new Longhorn node should eventually report:

- `READY=True`;
- `SCHEDULABLE=True`;
- a default disk using `/var/lib/longhorn`.

Adding a node does not automatically increase the replica count of existing volumes. This cluster currently uses `defaultReplicaCount: 1`. For high availability, use at least three storage-capable nodes and create or configure a StorageClass with `numberOfReplicas: "3"`; existing one-replica volumes must be migrated or otherwise rebuilt to gain additional replicas.
