> Historical outage handoff: migration subsequently resumed and completed on
> 2026-10-25. See [RESULTS.md](RESULTS.md) for final state; the investigation below
> is preserved and does not claim its root cause was fixed by this migration.

# Handoff: k3s/etcd outage during migration preflight

Recorded 2026-10-24 20:06 UTC. Workspace `/home/sup/code/bash_configs/rancher` on **proxmox3**.

## Requested task and current safety state

User authorized migrating **Sonarr, youtube-dl Material and AdGuard Home**, in
that order. No application was scaled down, switched to a new claim or copied.
No source data was modified by the migration. The attempt was blocked during
preflight by the Kubernetes control plane repeatedly restarting/failing etcd
readiness. Do not mark these apps migrated.

All six edited app `fleet.yaml`/`values.yaml` files were restored from the
preflight originals. The new storage bundle was not successfully applied and
has been removed from the watched Fleet tree. Planned target definitions are
preserved in `prepared-fleet-files.json` (path -> file text); do not activate
app target references until stopped copies/integrity checks are complete.
Other previous batches' uncommitted changes remain untouched. No commit/push.

## Blocker / evidence

- Local API: `https://127.0.0.1:6443` alternated connection refused, unexpected
  EOF, ServiceUnavailable/apiserver not ready and failed `/readyz?verbose`.
- Readiness specifically reported `[-]etcd failed` and `[-]etcd-readiness failed`;
  other listed checks passed. Reason withheld by the API response.
- Other API `https://10.0.0.72:6443` also returned ServiceUnavailable/apiserver
  not ready using the existing client credentials/CA with an explicit server.
- `systemctl show k3s` showed repeated restarts: NRestarts went from 4 to 5;
  it alternated active/running and activating/start. One active timestamp was
  2026-10-24 22:00:47 CEST; subsequent start began 22:02:22 CEST.
- `ss -tn '( dport = :2380 or sport = :2380 )'` showed no peer connections at
  the sampled time. This does not establish the root cause.
- Host had ~31Gi RAM, ~19Gi available, no swap at one sample; no OOM conclusion.
- Root journal access failed: `sudo: a password is required`; ordinary journal
  access could not see system messages. Root cause has NOT been diagnosed.
- No k3s restarts, firewall edits, etcd membership/data changes or recovery/reset
  operations were performed by this migration session.

Start with root `journalctl -u k3s --since '30 minutes ago'`, service logs,
etcd health/peer connectivity and the real restart reason. Existing local
`proxmox-allow-etcd-peer.sh` and `proxmox-remove-iptables-rule-blocking-etcd.sh`
were only inspected; no proof connects their subject to this outage. Do not
blindly run them or reset etcd. Restore stable etcd quorum/API readiness first.

## Preflight findings

All source workloads were initially singleton/available on **proxmox3**:
- `apps-sonarr/sonarr` Deployment.
- `apps-youtubedl-material/youtubedl-material` and separate
  `youtubedl-material-mongodb` Deployments (not StatefulSets).
- `apps-adguard-home/adguard-home` Deployment.

All six original claims are local-path, nominally 100Gi but mostly sparse.
Fresh read-only source measurement results:

| Source PVC | Allocated bytes | Apparent bytes | Proposed Longhorn request |
| --- | ---: | ---: | ---: |
| sonarr-config | 420487168 | 737885476 | 1Gi |
| youtubedl-material-appdata | 3202560 | 3936739 | 256Mi |
| youtubedl-material-users | 0 | 0 | 256Mi |
| youtubedl-material-mongodb-data | 524422656 | 740897674 | 1Gi |
| adguard-home-config | 4608 | 5736 | 256Mi |
| adguard-home-data | 832340480 | 3197271234 | 4Gi |

Total proposed: **6.75Gi per host / 13.5Gi aggregate** with two replicas,
`longhorn-rwo-2replicas`, RWO, singleton/Recreate, original PVCs kept for rollback.
Before this attempt: 23 migrated apps, 30 RWO production claims, 12Gi requested;
Longhorn physically free ~74.90Gi on proxmox2-old / 94.63Gi on proxmox3,
nominal remaining ~58.36Gi / 85.85Gi. Refresh after restoring control-plane health.
No active CloudCasa helper/kubemover was found at initial preflight.

## Objects created before the outage

These are temporary preflight/tooling resources, not migrated applications;
completion statuses could not be rechecked after the outage:

- Measurement Jobs: `sonarr-measure-longhorn-20261024` in apps-sonarr,
  `youtubedl-material-measure-longhorn-20261024` in apps-youtubedl-material,
  `adguard-home-measure-longhorn-20261024` in apps-adguard-home. Their size logs
  were successfully read; source PVCs mounted read-only.
- In apps-adguard-home: local-path 256Mi PVC and build Job both named
  `adguard-bbolt-tooling-20261024`. Job uses `golang:1.25-alpine`,
  `CGO_ENABLED=0`, `GOBIN=/tools`, `GOTOOLCHAIN=local`, builds
  `go.etcd.io/bbolt/cmd/bbolt@v1.4.3` on proxmox3. Need to verify it completed.
- Eight image-cache Jobs in apps-adguard-home named
  `batch-cache-APP-NODE-20261024`, APP one of sonarr, youtubedl-material,
  youtubedl-material-mongodb, adguard-home; NODE proxmox2-old/proxmox3.
  They use exact live images with `/bin/sh -c 'exit 0'`, no app process/data
  mount. Completion and cached digests need checking.
- `apps-adguard-home/adguard-dns-preflight-20261024`: Python Job, hostNetwork,
  dnsPolicy Default, pinned proxmox3; intended to print its resolver and test
  DNS. Created, but its result has NOT been retrieved.

Manifests for cleanup/review are in `/tmp` (same host):
`sonarr-ytdl-adguard-measure.json`, `sonarr-ytdl-adguard-cache.json`,
`adguard-bbolt-tooling.json`, `adguard-dns-preflight.json`.
Do not delete the tooling PVC until all bbolt checks/restores finish if resuming.

## Prepared files / remaining implementation

- `prepared-fleet-files.json` contains intended three app bundle/value updates
  and the six-PVC `longhorn-sonarr-ytdl-adguard-storage` bundle.
- Pinned charts rendered successfully to `/tmp/sonarr-sya-rendered.yaml`,
  `/tmp/youtubedl-material-sya-rendered.yaml`, `/tmp/adguard-home-sya-rendered.yaml`.
  Render invariants/image/secret/NFS comparisons are NOT yet checked.
- `copy-and-check.py` is adapted from prior batch: multi-claim copy + SHA256,
  SQLite quick checks when found, `--require-sqlite` makes zero DBs a failure
  for Sonarr. AdGuard needs bbolt checks; MongoDB needs separate recovery/full
  collection validation. Copy Jobs and execution helpers are NOT yet written.
- Original app definitions: `/tmp/longhorn-sonarr-ytdl-adguard-originals/repository-files.json`.
- Initial raw live snapshots: `/tmp/sonarr-ytdl-adguard-preflight.json`,
  `/tmp/sonarr-ytdl-adguard-longhorn.json`; re-fetch before any action.

## Engine-specific resume requirements

**Sonarr:** stop one writer, copy/check entire config incl WAL/SHM, require
SQLite quick_check for database(s), apply via Fleet, inspect target mount/rollout,
`/ping` + HTTPS login checks. Media NFS remains external.

**youtube-dl Material:** stop app first, wait gone, then MongoDB and wait gone.
Copy appdata/users/MongoDB together while all writers stopped. MongoDB directory
is `/bitnami/mongodb/data/db` under its mounted claim; WiredTiger, MongoDB
**9.0.4**. `/opt/bitnami/mongodb/bin/mongod`, `mongosh`, `mongodump` are present.
Exact live image is in preflight/render; do not substitute another Mongo version.
Validate a copied/isolated target engine using same binary, localhost binding
and no external Service, with full collection validation; do not use repair or
print private records/credentials. Record database/collection counts if possible.
The attempted live mongosh inventory was interrupted by the API outage;
`/tmp/ytdl-mongodb-before-inventory.json` is EMPTY/unusable, not evidence.
Bring MongoDB ready on target before starting app. Prepared values use
`mongodb.persistence.data.existingClaim`; confirm pinned chart renders it and
preserves secret references. Three NAS audio/subscription/video mounts stay NFS.

**AdGuard Home:** migrate last, after independent DNS/image/tool preflight.
Stats/session files are bbolt, expected under data/data/stats.db and sessions.db;
verify actual paths. Use pinned bbolt CLI against stopped-copy targets and a
representative restored backup; do not open/checkpoint originals. Config and
query/statistics/session data move together. Prepared values retain proxmox3
placement during cutover and preserve DNS LoadBalancer Services on both node
IPs. Verify UDP and TCP DNS responses and web UI after cutover.

Local host resolver is Tailscale `100.100.100.100` plus IPv6. Independent
`dig @1.1.1.1 oci.trueforge.org` worked; MagicDNS resolved the NAS to 10.0.0.20;
AdGuard `dig @10.0.0.50 example.org` worked before outage. CoreDNS config forwards
to `/etc/resolv.conf` and imports custom files; a safe complete independence
check is still outstanding. Cache tools/images before stopping DNS; don't
blindly change resolver configuration or rely on stopped AdGuard for recovery.

## Apply/validation rules

Read `fleet/AGENTS.md`. Use native helper
`longhorn/migrations/pilot-2026-10-24/apply-bundle.sh BUNDLE rancher/fleet/...`,
preserving GitRepo labels/targeting. Do not use direct Helm upgrades.
Use previous batch migration helpers as reference, but adapt the MongoDB stop/
start order and AdGuard bbolt verification. Protect originals with Helm keep/PV
Retain. Require stopped copies, checksums/integrity before target references.
Validate actual Fleet readiness, workloads, modes, replica health, endpoints,
DNS, NAS backups and isolated restore. Update inventory/completion/ranks only
when truly migrated; then remove temporary tools/jobs/PVCs. No commit/push unless
asked. Do not re-migrate earlier completed apps or interfere with unrelated edits.


## Debug follow-up (2026-10-24, approximately 22:12 CEST)

Read-only investigation from root on proxmox3; no service, firewall, etcd,
application or migration changes made.

Confirmed severe local etcd WAL sync latency:
- 21:48:02: fdatasync 1.558s and explicit missed-heartbeat warning.
- 21:58:54: fdatasync 8.602s.
- 22:01:12: fdatasync 8.430s.
- 22:01:36: fdatasync 14.231s.
- 21:59:27: fatal `leaderelection lost for k3s`, exit 1.
These establish storage stalls and a lease-election failure, but do not alone
prove the underlying hardware/load cause or every subsequent process exit.

Local NRestarts reached 8; another exit 1 occurred at 22:11:28. A previous exit
at 22:08:22 had status 2 without a captured panic/fatal explanation. Recovery
was temporary: both members returned matching applied indexes at term 254,
both endpoint-health proposals succeeded, and all API readyz checks passed;
then local API connection refused/EOF returned and the service restarted.
Do not treat one successful readiness sample as stable recovery.

The cluster has two voting members (10.0.0.50 and 10.0.0.72), no learners;
both are therefore required for quorum. Peer connection-refused errors on
10.0.0.72:2380 occurred during 22:02-22:04; established peer connections were
later present. No evidence justifies blindly changing firewall rules.

Local etcd resides on ZFS rpool/ROOT/pve-1, 325Gi available (29% used);
`zpool status -xv` says all pools healthy. Kernel search found no OOM kill in
the examined interval. This does not rule out storage latency or contention.

SSH as sup to 10.0.0.72 works with /home/sup/.ssh/id_rsa and the existing
/home/sup/.ssh/known_hosts. Root SSH is denied, sudo -n requires a password,
and the user cannot read the system journal. Peer service reports NRestarts=4,
ExecMainStartTimestamp 22:07:00 CEST, active timestamp 22:10:34 CEST.
Peer WAL metrics sampled approximately 22:12: sum 247.374s over 995 fsyncs
(~249ms mean since process start), indicating substantial peer sync latency
as well; distribution and root logs still need inspection. Peer memory had
~10Gi available, no swap; load average ~13 on this sample.

Next: obtain privileged peer journal/kernel logs for 21:45 onward, correlate
both hosts' WAL latency with ZFS/device latency and workload activity, and
explain the peer exits. Do not run a write benchmark against production etcd
storage or reset membership/data as a diagnostic step. Migration remains
blocked and all three apps remain unmigrated.
