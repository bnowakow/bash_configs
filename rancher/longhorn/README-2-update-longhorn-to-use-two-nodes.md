# Update Longhorn to use two nodes

This cluster has two Kubernetes nodes with Longhorn disks ready. The Helm
configuration is set to create two replicas for new Longhorn volumes.

## Configuration

The authoritative configuration is in `longhorn/helmchart.yaml`:

```yaml
defaultSettings:
  defaultReplicaCount: 2

persistence:
  defaultClassReplicaCount: 2
```

Apply the HelmChart:

```bash
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml \
  kubectl apply -f longhorn/helmchart.yaml
```

Wait for the Helm controller and Longhorn to reconcile:

```bash
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml \
  kubectl -n kube-system get helmchart longhorn

sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml \
  kubectl -n longhorn-system get pods
```

## Verify both Longhorn nodes

```bash
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml \
  kubectl -n longhorn-system get nodes.longhorn.io
```

Both Longhorn nodes should report `READY=True` and `SCHEDULABLE=True`, with a
healthy default disk using `/var/lib/longhorn`.

## Verify the StorageClass

Inspect the existing `longhorn` StorageClass:

```bash
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml \
  kubectl get storageclass longhorn -o yaml
```

Its parameters should include:

```yaml
parameters:
  numberOfReplicas: "2"
```

Check only the replica value:

```bash
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml \
  kubectl get storageclass longhorn \
  -o jsonpath='{.parameters.numberOfReplicas}{"\n"}'
```

Expected output:

```text
2
```

If the output is `1` or empty, the existing StorageClass is not explicitly
configured for two replicas. Inspect all StorageClasses before changing it:

```bash
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml \
  kubectl get storageclass
```

Use a new StorageClass configured with `numberOfReplicas: "2"` if the existing
StorageClass cannot be changed safely. Update new PVCs to use that class.

## Verify volumes

Adding a node or changing defaults does not increase replicas on existing
volumes. List the current Longhorn volumes:

```bash
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml \
  kubectl -n longhorn-system get volumes.longhorn.io \
  -o custom-columns=NAME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness,REPLICAS:.spec.numberOfReplicas
```

New volumes should show `REPLICAS` equal to `2`. Existing one-replica volumes
must be increased individually through the Longhorn UI or, after confirming
that both nodes have sufficient free space, with:

```bash
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml \
  kubectl -n longhorn-system patch volume <volume-name> \
  --type=merge \
  -p '{"spec":{"numberOfReplicas":2}}'
```

Monitor the volume until it becomes healthy:

```bash
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml \
  kubectl -n longhorn-system get volume <volume-name> -o yaml
```

## Availability note

With two storage nodes and two replicas, a volume can remain available after
one node fails, but it will be degraded until the node returns or a replacement
replica is created. Three storage nodes are recommended for replica count `3`
and stronger operational resilience.
