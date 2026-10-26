# Mailpile migration preparation blocked — 2026-10-26

User authorized Mailpile migration. **No Mailpile shutdown, source data copy,
source mutation, app Fleet cutover or production replica-policy change occurred.**
Both existing HTTPS endpoints responded 302 at the final service check. Local
k3s restart count increased 60→65; both APIs repeatedly returned 503/not-ready,
connection-refused and timeout errors. A bounded five-minute observation could
not establish a two-minute stable window. Peer I/O pressure was high (some 76%,
full 52% at one sample); service restart and hardware/storage diagnosis remain
separate work. The current non-root user cannot repair host I/O/etcd through
unavailable Kubernetes APIs.

## Actual source and revised target

`apps-mailpile/mailpile` still references original `mailpile-path1` 20Gi and
`mailpile-path2` 1Gi local-path claims. Last verified app state before instability:
1/1 Ready on proxmox2-old, current chart 10.0.4, exact image
`docker.io/rroemhild/mailpile:latest@sha256:5b58d53b2f11ba6ce360006ca1f6459970b3fba8bafdeafafbf1af1d14c58172`.
The older migration recipe used chart 10.0.3 and was rejected to avoid a downgrade;
new target definitions preserve the current 10.0.4 configuration and image.

Source data has grown: **10,102,524,988 logical bytes (~9.41GiB),
8,794,885,632 allocated bytes, 75,526 entries**. Key tree 600 bytes, three entries.
The old 9Gi Longhorn data staging claim cannot fit it. The existing Fleet storage
bundle now requests **12Gi data + 256Mi keys**, total 12.25Gi per host, RWO/two
production replicas. Native Fleet apply was accepted. **The expansion's final
filesystem capacity/conditions were not verified** because the APIs failed.
Do not treat the desired 12Gi value as completed expansion evidence.

Original source claims were not deleted/reclaimed by this task. The earlier
reclamation work intentionally excluded active Mailpile. Prior 25-Oct Longhorn
staging remains unverified and must be overwritten by a fresh stopped copy,
never activated or merged based on old partial data.

## Pending helper: cleanup request NOT accepted

The created Pod `apps-mailpile/mailpile-transfer-20261026` selects proxmox2-old.
Its transfer container is Python 3.13; its keyring container uses the exact app
image but overrides its command with sleep. It mounts original data/keys
**read-only** and the two Longhorn staging claims read-write. Both commands
are idle sleeps (86400s); **no Mailpile or copy process was started in it**.

After persistent API failures, eight attempts to delete only this helper all
failed; the final runtime list also failed. **Helper deletion is unconfirmed.**
When APIs recover, inspect its state and request normal deletion to detach the
staging volumes, unless the migration owner is deliberately resuming preparation.
Do not force-detach Longhorn volumes, delete source claims or restart Mailpile
independently. The live source service was not scaled down by this task.

```sh
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n apps-mailpile get deploy,pods,pvc -o wide
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n apps-mailpile delete pod mailpile-transfer-20261026 --ignore-not-found
```

## Evidence, logs and next steps

- UTC major-action audit: `ACTIONS.log` beside this file.
- Sensitive original deployment/repository/Secret snapshots and API error output:
  `/tmp/longhorn-mailpile-20261026/`, mode 700. Never commit or paste Secret data.
- New `prepared-fleet-files.json` is unapplied app configuration, preserving the
  current chart version. `transfer-pod.json` describes the preparation helper.
- `migrate.py` has been prepared but **not executed**. Do not start it until APIs
  remain healthy, k3s counts stabilize, pools have headroom, transfer helper is
  deliberately recreated/Ready and both staging targets are healthy with two
  running host replicas and the data filesystem actually reports 12Gi.
- Copy logic is rate-limited to 4MiB/s, verifies source/target bytes with SHA256,
  sparse files, owners, modes, timestamps and links. Require a stopped sole writer.
- Quiesced native NAS backups and independent full-manifest/GnuPG-clone restore
  validation precede cutover. A disposable strict-local **one-replica** restore
  on **proxmox3 only** avoids putting a duplicate 9.4GiB scratch replica on the
  constrained peer pool. Production remains **two replicas**. Verify that actual
  scratch placement before restoring/reading data.
- Original local data remains Retain/keep until explicit future reclamation.
  No completion marker/count increase has been made; migration is incomplete.

Resume ownership belongs to this migration session. Root troubleshooting should
restore control-plane/storage health and report changes; do not independently
scale workloads, run an uncapped copy or bypass the guard/verification steps.
