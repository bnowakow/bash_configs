# Installing a TrueCharts chart through Fleet

Most applications in `apps/` come from the TrueCharts OCI registry. Add a new
one the same way so `helm-upgrade-apps.sh`, the Longhorn NAS backups and the
ingress conventions all keep working. `apps/jenkins` and `apps/whisparr` are
complete, recent examples.

## 1. Inspect the chart

```sh
helm show chart  oci://oci.trueforge.org/truecharts/<app>   # latest version
helm show values oci://oci.trueforge.org/truecharts/<app>   # persistence keys, ports
```

Pin the version shown. Note the `persistence.*` key and `mountPath` that holds
the app's state, and the main service port.

## 2. Storage bundle: `infrastructure/<app>-storage/`

Create the PVC outside the chart so it survives uninstalls and upgrades.

`fleet.yaml`:

```yaml
name: <app>-storage
defaultNamespace: apps-<app>
dependsOn:
  - name: longhorn-pilot-storage
```

`pvc.yaml`: name it `<app>-<purpose>-longhorn-rwo`, with
`storageClassName: longhorn-rwo-2replicas`, the
`helm.sh/resource-policy: keep` annotation, and both backup labels:

```yaml
  labels:
    recurring-job.longhorn.io/source: enabled
    recurring-job-group.longhorn.io/nas-backup: enabled
```

## 3. App bundle: `apps/<app>/`

`fleet.yaml`:

```yaml
name: <app>
defaultNamespace: apps-<app>
dependsOn:
- name: <app>-storage
helm:
  chart: oci://oci.trueforge.org/truecharts/<app>
  version: <pinned version>
  releaseName: <app>
  waitForJobs: true
  valuesFiles:
  - values.yaml
```

The bundle `name` must equal the Helm release name: the upgrade script finds
the bundle and the OCI chart by it. Fleet v0.16 warns that `helm.chart` with an
OCI URL is deprecated. All apps still use it, and the upgrade script parses
it, so keep this form.

`values.yaml` essentials:

- `persistence.<key>`: `type: pvc`, `existingClaim: <the PVC above>`, and the
  chart's `mountPath`. NFS mounts use `server: nas.localdomain.bnowakowski.pl`
  with the same path on the NAS and inside the container (see Whisparr).
- `TZ: Europe/Warsaw`, `metrics.main.enabled: false`, and modest `resources`.
- The "two ingresses" convention is **one** `ingress.main` with two hosts,
  `<app>.rancher.tailscale.bnowakowski.pl` and
  `<app>.rancher.localdomain.bnowakowski.pl`, using `ingressClassName: traefik`,
  `integrations.certManager` (issuer `letsencrypt`), and
  `integrations.traefik` (`entrypoints: [websecure]`, `forceTLS: true`).
- Apps with SQLite or another single-writer state:
  `workload.main.replicas: 1` and `strategy: Recreate`.
- Authelia is used only by Homer. Apps with their own login don't get it.

Render before applying:

```sh
helm template <app> oci://oci.trueforge.org/truecharts/<app> --version <v> \
  -n apps-<app> -f apps/<app>/values.yaml | grep -n 'claimName\|host:\|mountPath'
```

## 4. Register it with the upgrade script

Add `<app>` to `truecharts_apps` in `rancher/helm-repositories.sh`. Otherwise
`helm-upgrade-apps.sh` may skip the app. If it must never be auto-upgraded,
add `'^<app>$'` to `exclude_patterns` in `rancher/helm-upgrade-apps.sh`
instead.

Both scripts may be running. Edit a copy and `mv` it into place so the running
bash process keeps its old file.

## 5. Apply and validate before committing

Always apply the bundles to the cluster so the change can be tested before any
commit or push (see `AGENTS.md`). Run from the repository root, storage first:

```sh
cd ~/code/bash_configs
K=/etc/rancher/k3s/k3s.yaml
fleet apply --kubeconfig $K --namespace fleet-local \
  --label fleet.cattle.io/repo-name=rancher-cluster \
  <app>-storage rancher/fleet/infrastructure/<app>-storage
fleet apply --kubeconfig $K --namespace fleet-local \
  --label fleet.cattle.io/repo-name=rancher-cluster \
  <app> rancher/fleet/apps/<app>
```

The GitRepo only re-runs on a new commit, so locally applied bundles stay
until the next push, which then includes them. Validate all of the following:

```sh
kubectl get bundledeployment -A -l 'fleet.cattle.io/bundle-name in (<app>,<app>-storage)' -o json \
  | jq -c '.items[]|{n:.metadata.name, idOk:(.spec.deploymentID==.status.appliedDeploymentID), ready:.status.ready, counts:.status.resourceCounts}'
kubectl -n apps-<app> get pvc,pods,ingress,certificate
kubectl -n apps-<app> wait certificate --all --for=condition=Ready --timeout=240s
curl -sS -o /dev/null -w '%{http_code} ssl=%{ssl_verify_result}\n' https://<app>.rancher.tailscale.bnowakowski.pl/
curl -sS -o /dev/null -w '%{http_code} ssl=%{ssl_verify_result}\n' https://<app>.rancher.localdomain.bnowakowski.pl/
```

Plain `http://` returning 404 is expected, since only `websecure` is routed.
Finally, add `apps/<app>/README.md` (version, storage, endpoints, first-start
steps, validation results) and a line in this directory's `README.md`.

If the app needs data from an existing PVC, that is a PVC migration. Follow
`rancher/AGENTS.md` and the Longhorn migration procedure instead.
