# Homer without authentication

This copies the Homer chart and editor with `homer-without-auth` hostnames.
It shares the `apps-homer` namespace so the copy Job can mount the original
`homer-config-longhorn-rwo` PVC read-only and its own
`homer-without-auth-config-longhorn-rwo` PVC. Both claims are managed by the
`longhorn-pilot-storage` bundle; the config-copy bundle declares no local-path claim.

Fleet installs `homer-without-auth-config-copy` after Homer, then waits for its
Job to finish before installing this instance. The Job copies all assets and
removes every line containing `type:`, `api_token:`, `apikey:`, `libraryType:`,
`auth:`, or `node:` from `/www/assets/config.yml` in the destination. The original
PVC is unchanged. Staging ensures the unfiltered config is never copied to the
served destination. Other files are copied unchanged.

The deployment Job runs once, with retries on failure. A CronJob also refreshes
the copy hourly, at minute zero (`0 * * * *`, Europe/Warsaw). Scheduled runs do
not overlap each other. Both use the same ConfigMap script and PVCs.

To refresh immediately, delete the completed deployment Job and let Fleet
recreate it:

```sh
kubectl -n apps-homer delete job homer-without-auth-config-copy-longhorn
```

The existing Homer authentication routes match only the original hostnames.
