# Ubooquity

Fleet deploys the pinned TrueCharts chart into `apps-ubooquity`, with a 1Gi
local-path PVC at `/config`. The NFS export
`nas.localdomain.bnowakowski.pl:/mnt/PlexPool/plex/Books` is mounted at `/books`.

Reader URLs:

- https://ubooquity.rancher.tailscale.bnowakowski.pl/ubooquity/
- https://ubooquity.rancher.localdomain.bnowakowski.pl/ubooquity/

Administration URLs:

- https://ubooquity-admin.rancher.tailscale.bnowakowski.pl/ubooquity/admin
- https://ubooquity-admin.rancher.localdomain.bnowakowski.pl/ubooquity/admin

The admin URL must have no trailing slash so its relative form requests resolve
correctly. Use these full paths: Ubooquity returns an error for `/`. Set an administrator
password through the administration interface after installation.

## Issues encountered during installation and setup

These observations are from the deployment of TrueCharts chart `16.0.0`
(Ubooquity `3.1.0`) on 2026-10-18.

### Root URLs return HTTP 500

Both reader and admin hostnames returned HTTP 500 at `/`, with
`Could not find matching provider (wrong URL)`. The pod was ready and its
certificates were valid; the requests were reaching Ubooquity.

Use `/ubooquity/` for the reader and `/ubooquity/admin` for administration, as
listed above. These paths returned HTTP 200. A healthy pod alone does not verify
that the requested application path works.

### Setting the admin password spins indefinitely

The admin password form loaded at `/ubooquity/admin/`, but submitting it left
the progress indicator running. The browser console showed:

```text
TypeError: Cannot read properties of undefined (reading 'length')
    at str2rstr_utf8 (sha256-min.js)
    at hex_hmac_sha256 (sha256-min.js)
    at password.js:18:57
```

The form requests `admin-res/cryptoparams` using a relative URL. With the trailing
slash, the browser requests `/ubooquity/admin/admin-res/cryptoparams`, which
returns HTML with HTTP 200 instead of JSON. Consequently `response.data.salt` is
undefined, the hash calculation fails, and the form never submits the password.
The actual endpoint `/ubooquity/admin-res/cryptoparams` returns JSON containing
`salt` and `time`.

The fix is the companion Fleet bundle
[`ubooquity-admin-redirect`](../ubooquity-admin-redirect/), which depends on this
bundle. Its Traefik middleware and IngressRoutes redirect the exact path
`/ubooquity/admin/` to `/ubooquity/admin` on both admin hostnames. The redirect
was verified as HTTP 302, and password setup worked after it was applied.
Keep this companion bundle when deploying Ubooquity.

If this happens again, reload the canonical admin URL and inspect the
`cryptoparams` request URL and response in the browser Network tab. HTTP 200
alone is insufficient: the response must be JSON with a defined `salt`.
Do not share passwords or password hashes when collecting diagnostics.

### Logs show missing Angular source maps

While investigating the password form, logs contained messages such as
`Admin page resource not found: angular.min.js.map`, with equivalent messages
for Angular Animate, Messages, and Aria. These concern browser debugging source
maps. They did not explain the form failure; the wrong salt-request URL did.
No source-map changes were needed.

### User sees only Raw Files despite Books permission

User `sup` could log in, but the library home at `/ubooquity/` displayed only
Raw Files. The saved `/config/preferences-2.json` correctly contained `/books`
in `opusPaths`, category `books`, and `sup` in its `userName` access list. Scans
completed successfully with 78 books, and the NFS mount was readable.
Logging out and back in after saving settings had not resolved it.

Restarting Ubooquity resolved the issue; the user confirmed Books became visible.
A stale in-memory per-user library/permissions cache is the suspected cause,
not a proven application defect. Neither the NAS mount nor the book files needed
changing.

If saved permissions are correct but the category remains missing, restart and
wait for the replacement pod, then log in again:

```sh
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n apps-ubooquity \
  rollout restart deployment/ubooquity
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n apps-ubooquity \
  rollout status deployment/ubooquity --timeout=180s
```

This briefly interrupts service. The deployment has a 60-second termination
grace period; the old pod took time to terminate before its replacement started.
The replacement became ready without warning events.

### Raw Files was initially shared from the pod root

The Raw Files share initially pointed to `/`, independently of the Books share
at `/books`. That exposed the pod filesystem to the permitted reader user.
It was subsequently changed to `/books`, as verified in the saved preferences.
Keep Raw Files restricted to `/books`, or disable Raw Files if it is unnecessary.
This setting is managed through Ubooquity's admin interface and stored on the
config PVC; changing the NFS mount does not update the share automatically.

### Helm upgrade HTTP precheck returned 500

The upgrade script originally requested `/` on every ingress host, which triggers
Ubooquity's wrong-URL error even when the app is healthy. Its TCP readiness
probes do not provide an HTTP path for checking the public reader/admin routes.

Each ingress now declares `helm-upgrade.bnowakowski.pl/check-path` in its chart
values: `/ubooquity/` for the reader and `/ubooquity/admin` for administration.
`helm-upgrade-apps.sh` reads this annotation for both prechecks and postchecks,
including certificate retries. Other ingresses default to `/` when the annotation
is absent. The script contains no Ubooquity-specific path mapping.

### Helm upgrade reported Fleet bundle not found

The Bundle existed, but its `fleet.cattle.io/repo-name: rancher-cluster` label
was missing after a direct local `fleet apply`. The upgrade script requires
this label before upgrading a GitRepo-managed release, so it rejected the Bundle.

After confirming the app belongs to the `rancher-cluster` GitRepo path, the
label was restored:

```sh
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n fleet-local \
  label bundle ubooquity fleet.cattle.io/repo-name=rancher-cluster --overwrite
```

Preserve existing Bundle labels when applying local changes. Do not bypass the
upgrade script's ownership check or use the shared GitRepo name as the pruning
scope of a single-bundle `fleet apply`.
