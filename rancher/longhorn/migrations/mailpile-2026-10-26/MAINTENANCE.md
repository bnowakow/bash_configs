# Temporary workload shutdown for Mailpile migration — 27 October 2026

## Latest restoration instruction —27October

After successful Mailpile migration, restore applications to **Fleet desired
state**, as explicitly requested by the user. This supersedes saved live replica
counts as the application restoration authority. `restore-fleet.py --plan`
validated all52 targets without changing workloads: applications/schedules map
to Fleet bundles and rendered manifests, supporting services outside Fleet use
the saved state. Current Fleet counts happen to match the saved application
counts, including Filebot at0; no count is guessed from an application name.

`quiesce-workloads.py restore` delegates to `/usr/bin/python3 restore-fleet.py`
(system PyYAML is installed). It requires STATE phasecomplete and reruns final
migration verification before restoration. Databases return first, applications
gradually with rollout and both-host pressure checks, supporting services and
schedules afterward; Fleet readiness must converge. RESTORATION.json is the
restoration completion record. The maintenance watcher invokes this automatically
once the migration has genuinely passed validation. No application restart has
been performed merely because the byte counter is near100%.

The original saved plan below remains an audit/recovery record. Its historical
restoration wording is superseded by this instruction.


The user authorized stopping everything practical to reduce I/O pressure, then
starting the migration. Mailpile's guarded copy had already started when the
shutdown was applied; it was deliberately left running. The source remains
scaled to zero, the helper mounts originals read-only, and original PVCs/PVs
are preserved. Copy remains capped at256KiB/s, restore hashing512KiB/s, with
pressure pauses at some10%/full2%. This maintenance changes live scale only;
Fleet application files are not rewritten to persist zero replicas.

## Scope and restoration

45 previously active workloads were requested at zero; Filebot and Mailpile
were already zero and remain so. Six CronJobs are suspended, including the
normal daily NAS schedule. An already-active native NAS backup was allowed to
finish. The migration's explicit pre-cutover NAS job is separate and can run
while the ordinary schedule is suspended.

Preserved services: AdGuard Home DNS, CoreDNS, ingress/networking, local-path
provisioner, cert-manager/admission webhooks, and Longhorn manager/engine/CSI
services and DaemonSets. Only Longhorn UI was stopped. Fleet agent/controllers,
optional Rancher/provisioning services, metrics and CloudCasa agents were
stopped temporarily. Rancher UI and most application URLs are unavailable.

Exact workload UIDs and replica counts are in [maintenance-plan.json](maintenance-plan.json).
Full original objects remain private under /tmp/longhorn-mailpile-20261026;
failed/partial inventory output is not used as a restoration baseline.

`quiesce-workloads.py stop` applies that saved plan. UID preconditions protect
against accidentally modifying a replacement resource. Applications receive
shutdown before database workloads; databases receive a grace interval.
`maintenance-watch.py` coordinates with the already-running migration:

1. Leave Fleet stopped during bulk copying.
2. After verified copy, restore only the Fleet controller.
3. Wait for the new Longhorn-claim Bundle and changed BundleDeployment ID;
   only then restore Fleet agent, so the old source bundle cannot restart.
4. After STATE.json reports complete (full backup/restore/runtime checks passed),
   run `quiesce-workloads.py restore`: databases first, then saved replica counts
   gradually, with rollout and I/O checks between workloads. Resume schedules last.

No automatic restoration is attempted if migration requires review. That avoids
reactivating stale source data or adding load during recovery. The saved plan
and ACTIONS.log make the remaining restoration explicit. Do not run restore-agent
or start another migration manually while the watcher is active.

Manual restoration after verified migration:

```sh
python3 longhorn/migrations/mailpile-2026-10-26/quiesce-workloads.py restore
```

Workloads originally at zero stay zero; Mailpile is excluded from maintenance
restoration because its successful migration controls its new instance.

## Effect

Repeated etcd readiness failures and peer I/O saturation motivated this step.
After scaling, compare physical pool free space, PSI, k3s restart counts and
copy progress in ACTIONS.log. Quiet application workloads reduce competing I/O;
this does not establish that the underlying NVMe/ZFS problem is repaired.

## Saved replica counts

| Namespace | Workload | Original replicas |
|---|---|---:|
| apps-audiobookshelf | deployment/audiobookshelf | 1 |
| apps-authelia | deployment/authelia | 1 |
| apps-bazarr | deployment/bazarr | 1 |
| apps-bindery | deployment/bindery | 1 |
| apps-bookstack | deployment/bookstack | 1 |
| apps-bookstack | deployment/bookstack-mariadb | 1 |
| apps-calibre | deployment/calibre | 1 |
| apps-calibre | deployment/calibre-web | 1 |
| apps-calibre | deployment/kavita | 1 |
| apps-cleanuparr | deployment/cleanuparr | 1 |
| apps-ddclient | deployment/ddclient | 1 |
| apps-docker-mailserver | deployment/docker-mailserver | 1 |
| apps-duckdns | deployment/duckdns | 1 |
| apps-filebot | deployment/filebot | 0 |
| apps-flaresolverr | deployment/flaresolverr | 1 |
| apps-homer-test | deployment/homer-test | 2 |
| apps-homer | deployment/homer | 1 |
| apps-homer | deployment/homer-without-auth | 1 |
| apps-jellyseerr | deployment/jellyseerr | 1 |
| apps-mailpile | deployment/mailpile | 0 |
| apps-openbooks | deployment/openbooks | 1 |
| apps-profilarr | deployment/profilarr | 1 |
| apps-prowlarr | deployment/prowlarr | 1 |
| apps-radarr | deployment/radarr | 1 |
| apps-scrutiny | deployment/scrutiny | 1 |
| apps-smokeping | deployment/smokeping | 1 |
| apps-sonarr | deployment/sonarr | 1 |
| apps-ubooquity | deployment/ubooquity | 1 |
| apps-uptime-kuma | deployment/uptime-kuma | 1 |
| apps-youtubedl-material | deployment/youtubedl-material | 1 |
| apps-youtubedl-material | deployment/youtubedl-material-mongodb | 1 |
| apps-zabbix | deployment/zabbix-zabbix-server | 1 |
| apps-zabbix | deployment/zabbix-zabbix-web | 1 |
| apps-zabbix | deployment/zabbix-zabbix-webservice | 1 |
| cattle-capi-system | deployment/capi-controller-manager | 1 |
| cattle-fleet-local-system | deployment/fleet-agent | 1 |
| cattle-fleet-system | deployment/fleet-controller | 1 |
| cattle-fleet-system | deployment/gitjob | 1 |
| cattle-fleet-system | deployment/helmops | 1 |
| cattle-system | deployment/rancher | 3 |
| cattle-system | deployment/system-upgrade-controller | 1 |
| cattle-turtles-system | deployment/rancher-turtles-controller-manager | 1 |
| cloudcasa-io | deployment/cloudcasa-kubeagent-manager | 1 |
| cloudcasa-io | deployment/kubeagent | 1 |
| kube-system | deployment/metrics-server | 1 |
| longhorn-system | deployment/longhorn-ui | 2 |
| apps-zabbix | statefulset/zabbix-postgresql | 1 |
