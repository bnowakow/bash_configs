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
