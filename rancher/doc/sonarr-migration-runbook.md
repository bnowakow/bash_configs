# Sonarr migration runbook

This documents the Sonarr migration into the Rancher Fleet/GitOps setup and the
lessons that apply to future applications with CloudCasa PVC backups.

## Final Sonarr layout

- Fleet bundle: `rancher/fleet/apps/sonarr`
- Chart: `oci://oci.trueforge.org/truecharts/sonarr`
- Chart version: `26.9.1`
- Release name: `sonarr`
- Namespace: `apps-sonarr`
- Config PVC: `sonarr-config`
- PVC storage class: `local-path`
- Ingress hosts:
  - `sonarr.rancher.tailscale.bnowakowski.pl`
  - `sonarr.rancher.localdomain.bnowakowski.pl`
- Certificates: cert-manager ClusterIssuer `letsencrypt`

The application values use an existing claim:

```yaml
persistence:
  config:
    existingClaim: sonarr-config
```

This is important. It makes the chart mount the restored PVC without rendering a
`PersistentVolumeClaim` resource for Helm/Fleet to manage.

## Recommended migration order

1. Prepare the infrastructure first:
   - K3s is healthy.
   - Fleet is healthy.
   - The storage class used by the backup exists.
   - CloudCasa is connected.
   - cert-manager and the required ClusterIssuer are ready.
   - Traefik is reachable if the application needs ingress.

2. Prepare the Fleet bundle in Git before installing the application.

   Use the real chart defaults from the pinned OCI chart and add local changes.
   Set `existingClaim` from the beginning if the PVC will be restored from
   CloudCasa. Do not initially install the chart with a chart-managed PVC and
   convert it later.

3. Commit and push the bundle.

4. If an old application is running, stop it before restoring its PVC:

   ```bash
   kubectl -n apps-sonarr scale deployment/sonarr --replicas=0
   kubectl -n apps-sonarr rollout status deployment/sonarr --timeout=5m
   ```

5. Restore only the required PVC from CloudCasa. For Sonarr this was
   `apps-sonarr/sonarr-config`. Wait until:

   ```bash
   kubectl -n apps-sonarr get pvc sonarr-config
   ```

   reports `Bound`, and CloudCasa reports the restore as `Completed`.

6. Start the application:

   ```bash
   kubectl -n apps-sonarr scale deployment/sonarr --replicas=1
   kubectl -n apps-sonarr rollout status deployment/sonarr --timeout=5m
   ```

7. Verify the application logs, PVC, ingress, certificates, and Fleet bundle.

## Critical PVC ownership warning

During this migration, the first Sonarr Helm revision rendered and owned the
PVC. The restored PVC was then changed to `existingClaim`. Although the new
manifest no longer contained a PVC, Helm removed the old PVC from the release
during the upgrade. Because the `local-path` PV had reclaim policy `Delete`, the
PV was deleted too.

The PVC had to be restored again.

Avoid this sequence in future migrations:

```text
install chart with a chart-managed PVC
        -> restore/replace PVC
        -> change chart to existingClaim
```

Use this sequence instead:

```text
prepare existingClaim in Git
        -> restore PVC
        -> let Fleet install/upgrade the application
```

If an already-installed release must be converted, stop the application and
protect the existing PVC before changing the release. Inspect the Helm release
manifest and resource policy first; do not assume that a PVC removed from the
new manifest will be retained. Confirm the PV reclaim policy before making any
Helm change.

Never delete the restored PVC or PV as a troubleshooting step unless the data
has been independently verified and another backup/restore plan is available.

## CloudCasa restore observations

For the successful Sonarr restore:

- The restore created a new `local-path` PV and bound it to `sonarr-config`.
- The mover transferred approximately 589 MB and 2,332 files.
- CloudCasa logs reported `Restore successful` / `Completed`.
- The restore custom resource may be cleaned up after completion, so its absence
  later is not itself a failure.
- The authoritative checks are the CloudCasa UI/job result, the bound PVC, and
  the application data/logs.

## Validation commands

### Fleet and Helm

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl -n fleet-local get gitrepo,bundle -o wide
helm -n apps-sonarr list -a
helm -n apps-sonarr get manifest sonarr | rg -n \
  'kind: PersistentVolumeClaim|claimName: sonarr-config|kind: Ingress'
```

The desired manifest should contain `claimName: sonarr-config` and should not
contain a rendered PVC for that claim.

### Application and storage

```bash
kubectl -n apps-sonarr get pod,deploy,svc,pvc -o wide
kubectl -n apps-sonarr logs deployment/sonarr --since=10m
kubectl -n apps-sonarr get events --sort-by=.lastTimestamp
```

Healthy Sonarr startup includes successful SQLite database opening/migrations,
`Now listening on: http://[::]:8989`, and a `1/1 Running` pod with no restart
loop.

### Ingress and certificates

```bash
kubectl -n apps-sonarr get ingress,certificate,certificaterequest,challenge,order
curl -k -I https://sonarr.example.invalid/
```

Expect valid certificates from the `letsencrypt` issuer and an HTTP response
from Sonarr. A `401 Unauthorized` response is useful evidence that Traefik
reached Sonarr and Sonarr authentication is working.

## Temporary Traefik exposure

This cluster currently has K3s ServiceLB disabled and kube-vip is not being used.
Therefore the temporary Traefik configuration uses host ports:

```yaml
ports:
  web:
    hostPort: 80
  websecure:
    hostPort: 443
```

The Traefik pods must be spread across the nodes so both replicas do not compete
for the same host ports. When kube-vip is reintroduced, remove the temporary
host-port approach and configure the load balancer deliberately during a
maintenance window.

## General lessons

- Restore data before starting an application that expects the restored PVC.
- Put the complete desired application configuration in Fleet values, including
  ingress and chart-specific overrides; do not rely on an old Helm release's
  values as the source of truth.
- Pin chart versions and verify the OCI chart renders successfully before push.
- Keep release name, chart name, namespace, and PVC names explicit in the bundle.
- Treat CloudCasa-created resources as externally owned. Use `existingClaim` for
  restored PVCs instead of forcing Fleet to own them.
- Ignore unrelated Fleet `Modified` status only after identifying the resource;
  CloudCasa may modify its own agent resources after deployment.
- Do not troubleshoot a failed application by deleting its PVC. First inspect
  pod events, PVC/PV state, Helm manifests, and CloudCasa restore status.

## Legacy Helm modification files

Once an application is migrated to Fleet, its Fleet bundle becomes the versioned
source of truth. Do not continue editing or applying the corresponding file under
`helm-apps-modifications/`; that directory belongs to the legacy/manual Helm
workflow.

The legacy files removed after migration were:

- `flaresolverr.yaml`
- `jellyseerr.yaml`
- `prowlarr.yaml`
- `radarr.yaml`
- `sonarr.yaml`

Their active configuration now lives under `fleet/apps/<application>/`, with
chart versions and values reviewed and committed together.
