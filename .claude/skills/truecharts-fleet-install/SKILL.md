---
name: truecharts-fleet-install
description: Install (or add) a TrueCharts Helm chart as a Fleet app in the rancher cluster, with a Longhorn storage bundle, the standard two-host Traefik ingress, the helm-upgrade-apps.sh registration, a Fleet apply and live validation. Use when the user asks to install/add/deploy an app from truecharts.org or oci.trueforge.org/truecharts.
---

# Install a TrueCharts chart through Fleet

Follow `rancher/fleet/TRUECHARTS.md` exactly; it is the source of truth. Use
`rancher/fleet/apps/jenkins` and `rancher/fleet/apps/whisparr` as templates.
Also obey `rancher/fleet/AGENTS.md` and `rancher/AGENTS.md`.

## Steps

1. `helm show chart|values oci://oci.trueforge.org/truecharts/<app>`: pin the
   latest version, find the state `persistence` key, its mountPath and the port.
2. Ask the user (AskUserQuestion) only about what the repo can't decide:
   the PVC size, NFS media mounts (NAS paths), Authelia (default: no, except
   Homer), and anything unusual in the chart (extra ports, required secrets or
   databases). Recommend the repo convention first.
3. Create `rancher/fleet/infrastructure/<app>-storage/{fleet.yaml,pvc.yaml}`
   (depends on `longhorn-pilot-storage`; `longhorn-rwo-2replicas`; `keep`
   annotation; both NAS-backup labels; PVC `<app>-<purpose>-longhorn-rwo`).
4. Create `rancher/fleet/apps/<app>/{fleet.yaml,values.yaml}`. The bundle name
   equals the release name, and the app depends on `<app>-storage`. The values
   use `existingClaim`, `TZ: Europe/Warsaw`, metrics off, and one `ingress.main`
   with the hosts `<app>.rancher.tailscale.bnowakowski.pl` and
   `<app>.rancher.localdomain.bnowakowski.pl`, cert-manager `letsencrypt`, and
   Traefik `websecure` with forceTLS. Single-writer apps get
   `replicas: 1` + `Recreate`.
5. `helm template … -f values.yaml` and confirm claimName, hosts and mountPath.
6. Add `<app>` to `truecharts_apps` in `rancher/helm-repositories.sh`.
   If `helm-upgrade-apps.sh` is running (`pgrep -af helm-upgrade-apps.sh`),
   edit a copy and `command mv -f` it into place. Never edit it in place.
7. **Always `fleet apply` both bundles** (storage first) from the repo root,
   with `--namespace fleet-local --label fleet.cattle.io/repo-name=rancher-cluster`,
   so the user can test before commit/push. zsh doesn't word-split variables,
   so write each command out explicitly.
8. Validate the live state: the BundleDeployment's appliedDeploymentID equals
   its deploymentID with Ready=true and full resourceCounts; the PVC is Bound
   and mounted; the pod is Ready; the certificates are Ready; and both HTTPS
   hosts return 200/302/401 with `ssl_verify_result=0`. Plain HTTP 404 is
   normal. Don't claim success from manifest generation alone.
9. Write `apps/<app>/README.md` (version, storage, endpoints, first start,
   validation results with date) and add a line to `rancher/fleet/README.md`.
10. Don't commit or push unless asked. Report what was applied, what was
    verified, and anything that wasn't.
