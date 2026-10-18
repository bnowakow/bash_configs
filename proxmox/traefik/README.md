# Traefik for Proxmox VE and Proxmox Backup Server

## Choose the deployment model first

### Model A — Proxmox VE or PBS without K3s

Use the native systemd Traefik service described in this README and
`PROXMOX_VE_TRAEFIK_INSTALL.md` only when no K3s ingress owns ports 80/443.
Traefik then forwards to the local loopback PVE (`:8006`) or PBS (`:8007`)
listener.

### Model B — Proxmox VE with K3s

If the Proxmox VE host runs K3s and K3s Traefik owns ports 80/443, do **not**
install or start the native `traefik.service`. Use the Kubernetes resources in
`pve-proxy.yaml` and follow `K3S_PVE_PROXY.md`; that configuration proxies PVE
as an external HTTPS backend without changing K3s Traefik's entrypoints.

This directory documents a native Traefik reverse proxy for either Proxmox VE
(PVE) or Proxmox Backup Server (PBS). Traefik owns ports 80 and 443, redirects
HTTP to HTTPS, obtains certificates with Cloudflare DNS-01, and forwards the UI
to the local Proxmox HTTPS listener.

| Deployment | Local upstream | Additional behavior |
| --- | --- | --- |
| PVE | `https://127.0.0.1:8006` | noVNC works through Traefik WebSockets. SPICE stays on direct TCP/3128. |
| PBS | `https://127.0.0.1:8007` | PBS has no PVE noVNC or SPICE proxy requirement. |

This host is `proxmox5`, currently running Proxmox VE without K3s.
Use the native service with `https://127.0.0.1:8006` and these names:

- `proxmox5.localdomain.bnowakowski.pl` (LAN `10.0.0.80`)
- `proxmox5.tailscale.bnowakowski.pl` (Tailnet `100.95.132.102`)

The PBS template is retained for other hosts. For a future K3s installation,
follow the handover in `K3S_PVE_PROXY.md` before enabling its ingress.

`dynamic/proxmox.yml.template` is the default PVE routing template, and
`dynamic/pbs.yml.template` is the PBS alternative. The active dynamic file and
`traefik.yml` are intentionally ignored because they contain selected domains
and the ACME contact email.
The Cloudflare token belongs only in `/etc/traefik/credentials/cloudflare-dns-api-token`; ACME
account keys and certificates belong only in `/var/lib/traefik/acme.json`.

The service uses checksum-verified upstream Traefik v3.7.15 at
`/usr/local/bin/traefik`. Use
[PROXMOX_VE_TRAEFIK_INSTALL.md](PROXMOX_VE_TRAEFIK_INSTALL.md) for installation,
operation, and the PVE/PBS differences.
