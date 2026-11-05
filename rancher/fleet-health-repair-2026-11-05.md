# Fleet health repair — 5 November 2026

The user-collected `fleet-health-inspection.txt` confirms five outstanding
bundles after the repository rename. The rename itself has synced successfully.

## Prepared changes

- `calibre-storage`: replace obsolete local-path PVC manifests with a retirement
  ConfigMap. The old claims were reclaimed in October; the inspection shows the
  Longhorn replacements Bound and used by Calibre, Calibre Web and Kavita.
  Keep the existing bundle as a record of retirement, without taking ownership
  of replacement claims already managed by `longhorn-calibre-arr-storage`.
- `cert-manager-resources`: add the two proxmox2-old DNS names already present
  in the live production issuer. Preserve the working solver configuration.
- `traefik-resources`: set the default/release namespace to `fleet-local`,
  matching the existing `pve-api` Helm annotation. Every bundled resource has
  its own explicit namespace, so resource placement does not change. The
  inspection found no Helm release record for this bundle in any namespace.
- `longhorn-backups`: make the release name explicit and adopt the existing
  `nas-daily-backup` RecurringJob into it with metadata changes. Its desired
  schedule, retention and concurrency match the live object.
- `cloudcasa`: set the chart image tag to the running
  `3.1.0-production.48`, rather than the chart default `3.1.0-prod`. The
  repair checks both manager and mover images before changing anything.

Chart image values are documented in the [upstream 3.4.7 values file](https://github.com/catalogicsoftware/cloudcasa-helmchart/blob/main/charts/v3.4.7/values.yaml).
Fleet namespace and release options are documented in the
[Fleet reference](https://fleet.rancher.io/reference/ref-fleet-yaml).
No drift-ignore rules or forced replacement are introduced.

## Apply and validate before committing or pushing

Run outside the agent network sandbox on proxmox3:

```bash
cd /home/sup/code/homelab/rancher
/usr/bin/python3 fix-fleet-health-2026-11-05.py
```

The script requires the existing `kubectl`, `fleet`, `helm`, `curl` and system
Python PyYAML installation. It writes a timestamped `fleet-health-repair-*`
directory containing `report.txt`, original objects and generated bundles.
These runtime files are for local review, not Git commits.

Before mutations, it checks Calibre claim non-use and replacement binding,
backup schedule equality, CloudCasa images and Helm ownership. It generates
all five bundles through Fleet and server-validates the generated resources,
preserving the exact existing GitRepo ownership labels and targeting. For
unready bundles it increments the saved sync generation to request a fresh
deployment attempt after ownership repair. It adopts unowned resources, resources already belonging to the
intended release, and the six individually verified legacy routes described
below, using resourceVersion checks. It refuses other conflicting owners and
does not enable permanent Helm ownership takeover.

It then stages the verified options and source files for native `fleet apply`,
which refreshes Fleet's Helm-values Secret as well as the Bundle. Each native
apply has a single-bundle prune scope, with a guard against other bundles in
that scope; GitRepo ownership labels and targeting are checked afterward.
This is necessary because offline Bundle generation plus `kubectl apply`
does not execute the values-Secret handling in Fleet's
[native apply implementation](https://github.com/rancher/fleet/blob/v0.16.3/internal/cmd/cli/apply/apply.go).
The script validates current Bundle generations,
BundleDeployment applied IDs, Calibre and CloudCasa rollouts, storage claim
references/binding, production issuer and PVE certificate readiness, and both
PVE HTTPS ingress endpoints. A failure stops the script with its report path;
changes already applied are retained for inspection. It does not commit or push.

No PVC migration, copying, storage deletion, credential rotation or k3s restart
is involved. The application shutdown procedure is not invoked for retiring
manifests of claims already absent from the cluster.

## Validation status

### Completed — 22:12:43 CET

The final user-run report is
`fleet-health-repair-20261105-221223/report.txt`. All five current Bundle
generations are Ready, and their BundleDeployments have matching desired and
applied IDs with Ready=True. The GitRepo reports **69/69 ready**, using
`https://github.com/bnowakow/homelab.git` at commit
`28375279fb74b542c92e4dd02502a7d8fbb1083a`.

- Calibre, Calibre Web, Kavita and CloudCasa rollouts succeeded.
- Running Calibre-group pods reference the expected Longhorn claims; all four
  Calibre-group claims are Bound.
- Production ClusterIssuer and PVE certificate are Ready.
- Both proxmox2-old localdomain and tailscale HTTPS ingress checks returned 200.
- Traefik's explicit empty endpoint conditions removed the final defaulting
  diff; endpoint address and port remain unchanged.

The final Fleet changes have been applied and validated before any further
commit/push. The repair scripts did not commit or push. This confirms Fleet and
the checked application endpoints, not a new backup run or restore test.
The failed historical `traefik-config/default` Helm record remains untouched;
the earlier caution about manually uninstalling that record still applies.

### Earlier attempts and diagnosis (historical)

At **22:09:33 CET**, `fleet-field-ownership-20261105-220933/report.txt`
confirmed both narrow field-ownership patches. Server dry runs and actual
responses preserved resource UIDs and configurations. Targeted bundle sync
generations advanced from 8 to 9.

The following validation run (`fleet-health-repair-20261105-220934/`) confirmed
CloudCasa Ready at 22:09:53, as well as the already-ready Calibre storage,
cert-manager resources and Longhorn backups. Traefik resources installed but
reported EndpointSlice drift: the desired endpoint omitted `conditions`, while
the API stores `conditions: {}`. The repository manifest now explicitly includes
that empty object. Fleet generation passed and its endpoint data, ports and
addressType exactly match the captured live object. This normalization still
needs applying with `fix-fleet-health-2026-11-05.py`; it does not change the
endpoint IP or readiness semantics. The existing monitor can remain running
while the new invocation applies this final change and validates all five
bundles. Do not rerun the field-ownership repair, whose old ownership claims
have already been removed.

The third run (`fleet-health-repair-20261105-211151/`) used native Fleet apply
at 21:11 CET. Calibre storage, cert-manager resources and Longhorn backups
became Ready. The `fleet-pending-inspection.txt` agent logs identify two further
server-side apply conflicts:

- `pve-proxy/pve-api-ipv4` EndpointSlice: the old
  `kubectl-client-side-apply` manager owns `endpoints`.
- `cloudcasa-io/cloudcasa-kubeagent-manager` Deployment: the CloudCasa updater
  owns `MY_POD_NAME.valueFrom.fieldRef`.

The monitor ended at **21:22:07 CET**, timing out on CloudCasa and Traefik
resources. The other three bundles were Ready. Final rollout, storage and
ingress checks were not reached. Snapshots and the failure report remain in
`fleet-health-repair-20261105-211151/`. A separate
`fix-fleet-field-ownership-2026-11-05.py` script is prepared to relinquish
only those two field claims in the named managers' `metadata.managedFields`,
preserving all unrelated ownership records. It checks the current object
values and Helm release owner, saves originals, server-dry-runs both patches,
and uses resourceVersion plus managedFields test preconditions. It verifies
that resource UIDs and all non-metadata/status payloads remain identical after
each patch. It then increments only those two bundles' sync generations.
No workload specification, endpoint address or pod-name reference is changed
by the metadata repair itself. After this metadata repair, rerun
`fix-fleet-health-2026-11-05.py` to confirm the subsequent Fleet deployments
and execute rollout/ingress checks; the previous monitoring process has exited.
No field-ownership repair report was present when this timeout was reviewed.

Kubernetes supports non-apply patches to managedFields but discourages manual
updates in ordinary operation; see its [field management documentation](https://kubernetes.io/docs/reference/using-api/server-side-apply/#field-managers).
This narrowly scoped, backed-up repair addresses the exact conflicts recorded
by the Fleet agent, rather than clearing entire ownership records or enabling
forced resource replacement. Syntax and ownership-pruning checks passed;
actual application and results still require the user-run script's report.

The second user-run attempt (`fleet-health-repair-20261105-205942/`) applied
the ownership patches and all five generated Bundle objects at 20:59 CET.
Calibre storage and cert-manager resources were Ready. At 21:09:50 the run
ended without readiness for CloudCasa, Longhorn backups and Traefik resources.
CloudCasa's applied deployment ID differed from its desired ID; the other two
still reported failed installs from before ownership repair. Matching an
applied ID alone did not establish installation success. The later rollout,
mount and ingress validations did not execute.

The script is now corrected to use native `fleet apply` (including values
Secret handling) and request a new sync generation for unready bundles. It
also saves snapshots during polling, logs condition messages when they change,
and requires BundleDeployment Ready=True as well as matching deployment IDs.
Native staged generation and preservation of targeting/sync generation passed
offline checks for all four raw bundles. This corrected version still needs
to be run on proxmox3; it has not yet been applied.

The first user-run attempt at 20:54 CET stopped during ownership preflight:
`adguard-home-cors` has a different Helm release owner. All five bundles were
generated and server dry-run validation passed, but **no ownership patches or
bundle applies ran**. The failure message's generic reference to retained
changes does not imply that this attempt mutated the cluster. Original
snapshots and the report are in `fleet-health-repair-20261105-205453/`.
Inspect the legacy `traefik-config` release and route ownership before retrying;
do not force ownership takeover.

The subsequent `traefik-ownership-inspection.txt` confirms that six AdGuard Home
and Jellyseerr Middleware/IngressRoute resources still have
`traefik-config/default` annotations. Every live spec exactly matches the
desired `traefik-resources` manifest. The current `traefik-config` Bundle is
Ready and contains only `kube-system/traefik` HelmChartConfig; it no longer
declares the routes. The failed historical Helm manifest still lists them,
PVE resources and the `pve-proxy` Namespace. Do not run `helm uninstall` against
that historical release: it could delete live resources. Its release record is
left intact by this repair. Any future manual recovery/upgrade of that legacy
Helm record must account for those obsolete entries rather than replaying or
pruning the stored manifest.

The revised repair permits only those six exact identities to transfer from
`traefik-config/default` to `traefik-resources/fleet-local`, after confirming
their live specs still match Git, the historical release remains failed, and
the current source Bundle is reconciled, Ready and contains only the
HelmChartConfig. All other ownership conflicts still stop the repair before
mutation. This is an ownership transfer of existing routes, not deletion or
recreation of their resources.

Local Python syntax and YAML parsing passed. All five bundles were generated
and server dry-run validated in user-run preflight. The agent sandbox still
blocks the Kubernetes socket. All final readiness, rollout and ingress checks
remain required on proxmox3 with the corrected script. Do not mark these
changes fully validated until that report confirms success.
