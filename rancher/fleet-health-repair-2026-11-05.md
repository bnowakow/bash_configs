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
preserving the exact existing GitRepo ownership labels, targeting and sync
generation. It adopts only unowned resources or resources already belonging
to the intended release, using resourceVersion checks. It refuses conflicting
owners and does not enable permanent Helm ownership takeover.

It then applies the generated bundles and validates current Bundle generations,
BundleDeployment applied IDs, Calibre and CloudCasa rollouts, storage claim
references/binding, production issuer and PVE certificate readiness, and both
PVE HTTPS ingress endpoints. A failure stops the script with its report path;
changes already applied are retained for inspection. It does not commit or push.

No PVC migration, copying, storage deletion, credential rotation or k3s restart
is involved. The application shutdown procedure is not invoked for retiring
manifests of claims already absent from the cluster.

## Validation status

Local Python syntax and YAML parsing passed. Fleet generated the four raw
manifest bundles successfully. Live application and server validation remain
pending because the agent sandbox blocks the Kubernetes socket. CloudCasa
chart generation and all rollout/ingress checks must run on proxmox3 with
the script above. Do not mark these changes deployed until that report confirms
success.
