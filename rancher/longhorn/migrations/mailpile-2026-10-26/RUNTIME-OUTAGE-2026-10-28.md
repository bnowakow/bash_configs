# Mailpile runtime outage — 2026-10-28T18:56:07+00:00

This is a later runtime incident after successful migration, full source/restore verification and application restoration. Historical completed checks do not establish current health.

- User reported Internal Error on `/profiles/`, followed by no available server.
- Observed HTTPS `/` and `/profiles/`:503, response `no available server` (Traefik has no usable backend).
- Both Mailpile Longhorn volumes are attached on proxmox3 but degraded again; desired replicas remain2. Last queried node/disk conditions reported Ready/Schedulable, not disk capacity failure.
- Peer full I/O PSI avg10 reached74.20%, some90.73%; backing-pool free39,812,276,224bytes. Severe I/O pressure accompanies the outage; root cause is not proven.
- Local API refused connections transiently. Local k3s subsequently showed active/running,NRestarts179. Peer verbose readiness briefly passed, but direct Mailpile API queries later returned ServiceUnavailable/apiserver not ready from both endpoints.
- Current Pod/endpoint/log state could not be reliably retrieved. Do not assert a Mailpile application exception, stopped Pod, corrupt data, or specific cause of the earlier500 without logs.
- No new migration copy or verification is running. Original Mailpile PVCs and verified NAS backup records are retained. No restart, scale-down, volume deletion or configuration mutation was performed during this diagnostic turn.

Stabilize API/etcd and investigate host I/O pressure, then inspect Mailpile Pod readiness/endpoints/logs and current engine replica modes. Preserve live Longhorn data and do not switch back to stale local originals. The API outage currently blocks a reliable application diagnosis.

## Recovery investigation — 2026-10-28T19:02:47.529938+00:00

- Confirmed peer `/var/lib/longhorn` is ext4 on `/dev/zd0`. Two one-second samples showed approximately 250 MiB/s reads on that device, 99–100% utilization and 21–24 ms read latency. Underlying NVMe showed 91–92% utilization and 63–75 ms write latency. These short samples establish substantial storage activity/latency, not which process caused it.
- Peer ZFS rpool reports healthy, but physical free space was approximately 35.17 GiB. This differs from free space inside the Longhorn ext4 filesystem.
- Latest sampled full I/O PSI: peer24.56%, local14.70%; local k3s NRestarts181. Peer API explicitly failed etcd/etcd-readiness. Backup/rebuild inventory unavailable through the unstable API.
- Recommended recovery order: identify and pause nonessential bulk storage activity; if necessary temporarily quiesce application workloads using a fresh replica/schedule snapshot, preserving Kubernetes/DNS/admission/Longhorn/CSI; investigate host disk/ZFS/etcd latency with root access; restore applications gradually after stable API and storage health. Do not blindly restart k3s, stop Longhorn engines, or reuse the migration's obsolete shutdown snapshot. No new workload or storage changes performed.

## Observed recovery completion — 2026-10-28T19:23:54.627477+00:00

Read-only minute monitoring observed degraded volumes fall4→2→1→0, ending with43 healthy volumes and4 detached/unknown volumes. All attached volumes, including both Mailpile volumes, are healthy. Both API readiness endpoints passed. k3s restart counts stayed186(proxmox3)/91(proxmox2-old) during this monitoring interval. Final full I/O PSI avg10 was0.30% local and1.53% peer. No recovery settings or workloads were changed during monitoring. This is observed current recovery, not proof the underlying recurring I/O/control-plane problem is resolved.
