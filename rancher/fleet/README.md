# Rancher Fleet configuration

This directory is intended to be configured as a Fleet GitRepo path. The Git repository
root is the parent `bash_configs` directory, so the GitRepo path is `rancher/fleet`.

Each child directory containing a `fleet.yaml` is a separate Fleet bundle:

- `infrastructure/longhorn` installs Longhorn from its official Helm repository.
- `infrastructure/cert-manager` installs cert-manager from its official OCI registry.
- `infrastructure/cloudcasa` installs the CloudCasa agent after Ansible creates its
  external values Secret.
- `infrastructure/traefik` manages the K3s Traefik `HelmChartConfig`.
- `infrastructure/cert-manager-resources` contains cert-manager resources that should be
  added after cert-manager is healthy.
- `apps/sonarr` installs Sonarr from the TrueCharts OCI registry with the repository's
  customized values.

The chart versions are deliberately pinned. Upgrade them through a reviewed Git change.

OCI is preferred where the chart publisher provides an official OCI distribution. The
current Longhorn documentation publishes the chart through `https://charts.longhorn.io`,
so that official repository is retained for Longhorn. cert-manager is configured to use
its official OCI chart at `oci://quay.io/jetstack/charts/cert-manager`.

## Connecting this directory to Fleet

Create a Fleet `GitRepo` in the Fleet management cluster, using this repository and the
`fleet` path. The exact repository URL and branch are environment-specific and should not
be committed here.

Example shape:

```yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: rancher-cluster
  namespace: fleet-local
spec:
  repo: https://example.invalid/replace-with-this-repository.git
  branch: main
  paths:
    - rancher/fleet
```

Do not apply the example unchanged.

## Migration warning

The existing cluster currently installs Longhorn through K3s' `HelmChart` resource at
`../longhorn/helmchart.yaml`. Do not enable the Fleet Longhorn bundle while that resource
is still managing the same Helm release. First inspect the existing Helm release, then
remove or disable the K3s `HelmChart` and let Fleet take ownership during a maintenance
window.

The same ownership rule applies to cert-manager: only one controller should manage its
Helm release.

These files define the desired state; they do not restore CloudCasa PVC backups. Restore
the data after Longhorn and the storage prerequisites are healthy, before enabling
application bundles that depend on those PVCs.
