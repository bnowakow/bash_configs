# Traefik for Proxmox VE and Proxmox Backup Server

This directory documents a native Traefik reverse proxy for either Proxmox VE
(PVE) or Proxmox Backup Server (PBS). Traefik owns ports 80 and 443, redirects
HTTP to HTTPS, obtains certificates with Cloudflare DNS-01, and forwards the UI
to the local Proxmox HTTPS listener.

| Deployment | Local upstream | Additional behavior |
| --- | --- | --- |
| PVE | `https://127.0.0.1:8006` | noVNC works through Traefik WebSockets. SPICE stays on direct TCP/3128. |
| PBS | `https://127.0.0.1:8007` | PBS has no PVE noVNC or SPICE proxy requirement. |

The installed deployment on this host is PBS. It uses
`proxmox-backup-server.localdomain.bnowakowski.pl` and
`proxmox-backup-server.tailscale.bnowakowski.pl`, with one Let’s Encrypt
certificate covering both names.

`dynamic/proxmox.yml.template` is the default PVE routing template, and
`dynamic/pbs.yml.template` is the PBS alternative. The active dynamic file and
`traefik.yml` are intentionally ignored because they contain selected domains
and the ACME contact email.
token belongs only in `/etc/traefik/credentials/cloudflare-dns-api-token`; ACME
account keys and certificates belong only in `/var/lib/traefik/acme.json`.

The service uses checksum-verified upstream Traefik v3.7.13 at
`/usr/local/bin/traefik`. Use
[PROXMOX_VE_TRAEFIK_INSTALL.md](PROXMOX_VE_TRAEFIK_INSTALL.md) for installation,
operation, and the PVE/PBS differences.
