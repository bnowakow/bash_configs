# Fleet health repair — 5 November 2026

Completed on proxmox3 at **22:12:43 CET (21:12:43 UTC)**. The
`rancher-cluster` GitRepo in `fleet-local` reported **69/69 ready** after
repairing five bundles. Its repository URL was
`https://github.com/bnowakow/homelab.git`, branch `master`, path `rancher/fleet`,
and synced commit `28375279fb74b542c92e4dd02502a7d8fbb1083a`.
The final EndpointSlice normalization was applied from the working tree; the
reported GitRepo commit alone does not include every local repair change.

The repository rename had already synced successfully before this repair.
Initial Fleet readiness was 64/69. There was no complete before-rename health
baseline establishing that all five issues predated the rename.

## Changes and causes

| Bundle | Observed problem | Completed repair |
| --- | --- | --- |
| `calibre-storage` | Fleet tracked the missing local-path `calibre-library` and `calibre-web-config` PVCs, reclaimed after their October migration. | Replaced the obsolete claim manifests with a retirement ConfigMap. Active Longhorn claims retain ownership under `longhorn-calibre-arr-storage`. |
| `cert-manager-resources` | Production issuer drift: live DNS solvers already included the two proxmox2-old names absent from Git. | Added `proxmox2-old.localdomain.bnowakowski.pl` and `proxmox2-old.tailscale.bnowakowski.pl` to the production solver in Git. |
| `longhorn-backups` | Existing `nas-daily-backup` RecurringJob lacked the Helm ownership metadata required for installation. | Adopted it under `longhorn-backups/longhorn-system` and made the release name explicit. Verified schedule, retention and concurrency matched Git before adoption. |
| `cloudcasa` | The chart default image was `3.1.0-prod`, while the running manager and mover used `3.1.0-production.48`. A later server-side apply attempt conflicted with the updater's ownership of `MY_POD_NAME.valueFrom.fieldRef`. | Pinned the current running image in Fleet and relinquished only the updater's fieldRef ownership claim, allowing Fleet to reconcile. |
| `traefik-resources` | Release namespace mismatch, six routes with legacy ownership, unowned PVE resources, then an EndpointSlice field-ownership conflict and API-defaulting diff. | Set release/default namespace to `fleet-local`, repaired ownership, relinquished the old client's endpoint field claim, and explicitly included `conditions: {}` in the endpoint manifest. |

All Traefik resources retain their explicit namespaces. The endpoint remains
`10.0.0.72:8006`. The six transferred legacy routes were the Middleware and
localdomain/tailscale IngressRoutes for AdGuard Home and Jellyseerr. Their live
specifications matched Git before transfer. The current `traefik-config`
Bundle was confirmed Ready and declared only the `kube-system/traefik`
HelmChartConfig, without those routes.

No PVC copying, migration or storage deletion occurred during this repair.
Calibre's retired claims were already absent and their replacement claims were
Bound and in use. No cluster-wide application shutdown was needed for this
manifest retirement. No credentials were rotated and no k3s restart occurred.

## Application and validation

The user ran the scripts outside the agent's network sandbox, which denied
connections to the local Kubernetes API. Explicit access used
`/etc/rancher/k3s/k3s.yaml`; kubeconfig files were not modified.

[The Fleet repair script](fix-fleet-health-2026-11-05.py) backs up objects,
checks claim use, schedule equality and ownership, generates only the five
bundles, and server-dry-runs the generated objects before mutations. Native
`fleet apply` performs the actual application, including Fleet Helm-values
Secret handling. Each apply uses a guarded single-bundle prune scope and
preserves the live GitRepo ownership labels and targeting. Unready bundles
receive a new sync generation to retry after ownership fixes.

[The field-ownership repair](fix-fleet-field-ownership-2026-11-05.py) removed
only these two claims from the named managers' `metadata.managedFields`:

- `pve-proxy/pve-api-ipv4`: `endpoints`, owned by
  `kubectl-client-side-apply`.
- `cloudcasa-io/cloudcasa-kubeagent-manager`:
  `MY_POD_NAME.valueFrom.fieldRef`, owned by `cloudcasa-kubeagent-manager`.

Both patches passed server dry runs, used resourceVersion and managedFields
test preconditions, and preserved unrelated ownership. Actual patch responses
confirmed unchanged resource UIDs and all non-metadata/status configuration.
Neither resource was deleted or recreated. There are no permanent drift-ignore
rules, broad field-ownership resets or forced resource replacements.

Final validation confirmed:

- Every repaired Bundle's observed generation matched its current generation
  and had Ready=True. Each BundleDeployment had Ready=True and matching
  desired/applied deployment IDs.
- Calibre, Calibre Web, Kavita and CloudCasa rollouts succeeded.
- Running Calibre-group pods referenced the expected Longhorn claims. All four
  claims (`calibre-config-longhorn-rwo`, `calibre-library-longhorn-rwo`,
  `calibre-web-config-longhorn-rwo`, `kavita-config-longhorn-rwo`) were Bound.
- Production `letsencrypt` ClusterIssuer and `pve-proxy/pve-ui` Certificate
  were Ready.
- Both `https://proxmox2-old.localdomain.bnowakowski.pl/` and
  `https://proxmox2-old.tailscale.bnowakowski.pl/` returned HTTP 200 with TLS
  verification enabled.
- GitRepo readiness was 69/69, without a displayed status error.

| Bundle | Validated generation | Sync generation |
| --- | ---: | ---: |
| `calibre-storage` | 3 | 7 |
| `longhorn-backups` | 3 | 8 |
| `traefik-resources` | 12 | 11 |
| `cert-manager-resources` | 7 | 7 |
| `cloudcasa` | 25 | 10 |

These checks confirm Fleet reconciliation and the listed workloads/endpoints.
They do not constitute a new backup execution or restore test. The repair
scripts did not commit or push changes.

## Evidence and earlier attempts

Times below are CET on 5 November 2026. Runtime report directories contain
original objects, generated bundles and final snapshots; they are local
incident evidence rather than application manifests.

| Attempt/report | Outcome |
| --- | --- |
| `fleet-health-repair-20261105-205453/report.txt` | Stopped in ownership preflight; no cluster mutations. Revealed legacy route ownership. |
| `fleet-health-repair-20261105-205942/report.txt` | Applied ownership patches and offline-generated Bundle objects. Calibre storage and issuer became Ready; three bundles remained unready at timeout. |
| `fleet-health-repair-20261105-211151/report.txt` | Corrected native Fleet apply and targeted retries made Longhorn backups Ready. Timed out at 21:22:07 on two server-side apply conflicts. |
| `fleet-field-ownership-20261105-220933/report.txt` | Confirmed both narrow ownership repairs and sync generations 8→9. |
| `fleet-health-repair-20261105-220934/report.txt` | CloudCasa became Ready. Traefik installed but showed the endpoint defaulting diff. |
| `fleet-health-repair-20261105-221223/report.txt` | Final endpoint normalization applied; all checks passed at 22:12:43. |

An early repair-script error applied offline-generated Bundle YAML with
`kubectl`, skipping native Fleet's Helm-values Secret handling. The script was
corrected to use native `fleet apply`. Matching an applied deployment ID alone
also proved insufficient: the final checks require Ready=True in addition.

The temporary `fleet-health-inspection.txt`, `traefik-ownership-inspection.txt`
and `fleet-pending-inspection.txt` were diagnostic inputs. Their findings and
final results are recorded here, so those text captures may be removed.
Keep the timestamped report directories if detailed before/after evidence is
wanted. No incident repair needs rerunning after successful completion;
especially do not rerun the field-ownership script against already-removed
claims.

## Historical Helm record left intact

The failed Helm release record `traefik-config` in `default` still contains
obsolete route/PVE entries, including the `pve-proxy` Namespace. It was not
uninstalled or rewritten. The active Fleet `traefik-config` Bundle is Ready
and declares only HelmChartConfig; the repaired `traefik-resources` Bundle
owns the routes and PVE resources.

**Do not run `helm uninstall` on that historical release:** its stored manifest
could cause live resources to be deleted. A future manual recovery, upgrade or
cleanup of that record must account for its obsolete entries before acting.
NAS symlink cleanup and separately authorized host Traefik service restarts
remain outside this repair.

## Implementation references

- [Fleet apply implementation](https://github.com/rancher/fleet/blob/v0.16.3/internal/cmd/cli/apply/apply.go): native apply refreshes Helm-values Secrets; offline output does not.
- [CloudCasa chart 3.4.7 values](https://github.com/catalogicsoftware/cloudcasa-helmchart/blob/main/charts/v3.4.7/values.yaml): image repository/tag configuration.
- [Kubernetes server-side apply](https://kubernetes.io/docs/reference/using-api/server-side-apply/): field conflicts and managedFields. Manual updates are discouraged in ordinary operation; this incident used exact, backed-up ownership changes after confirming agent errors.
