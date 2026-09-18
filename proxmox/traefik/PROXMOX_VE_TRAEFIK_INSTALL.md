# Traefik access for Proxmox VE and Proxmox Backup Server

This guide covers a native Traefik service that exposes the local Proxmox web
interface on HTTPS/443. It applies to both Proxmox VE (PVE) and Proxmox Backup
Server (PBS); select the appropriate local upstream and product-specific
behavior below.

## What is shared

Both products use the same native Traefik service, Cloudflare DNS-01 ACME
resolver, HTTP-to-HTTPS redirect, client-network allow-list, and security
headers. The local Proxmox service presents a locally generated certificate, so
the loopback servers transport uses `insecureSkipVerify: true`. Client TLS
remains validated by the Let’s Encrypt certificate served by Traefik.

Before installing, confirm that no other service owns ports 80 or 443:

```sh
ss -ltnp '( sport = :80 or sport = :443 )'
iptables-save -t nat | rg -C 3 -- '--dport (80|443)'
```

Do not run this native service on a K3s node where ServiceLB redirects host
ports 80 or 443 to the Kubernetes Traefik service.

## Product differences

| Item | Proxmox VE | Proxmox Backup Server |
| --- | --- | --- |
| Local HTTPS upstream | `https://127.0.0.1:8006` | `https://127.0.0.1:8007` |
| Dynamic service and transport names | Any consistent PVE names | Any consistent PBS names |
| WebSockets | noVNC is forwarded automatically | Standard PBS UI traffic only |
| SPICE | Direct plain HTTP CONNECT listener on TCP/3128 | Not used |

For PVE, do not tunnel SPICE through Traefik. `remote-viewer` receives a `.vv`
file that points to `http://<ui-hostname>:3128`; keep `spiceproxy.service`
running and protect TCP/3128 with the PVE firewall or an equivalent host
firewall. Traefik protects only the HTTPS UI.

## Current PBS deployment

This host runs PBS, not PVE. The installed configuration is:

| Setting | Value |
| --- | --- |
| Upstream | `https://127.0.0.1:8007` |
| LAN name | `proxmox-backup-server.localdomain.bnowakowski.pl` |
| Tailnet name | `proxmox-backup-server.tailscale.bnowakowski.pl` |
| Permitted clients | `10.0.0.0/8` and `100.64.0.0/10` |
| Certificate | One DNS-01 Let’s Encrypt certificate with both names as SANs |

The 30-second DNS propagation delay is intentional: Cloudflare DNS updates for
the Tailnet name required additional time before Let’s Encrypt could observe
the TXT challenge record.

## Native installation

The tracked templates, `traefik.service`, and these documents are the source
of truth. Do not commit live `traefik.yml`, `dynamic/pbs.yml`,
`/etc/traefik/traefik.env`, credentials, or `/var/lib/traefik/acme.json`.

For PBS, copy `traefik.yml.template` to `traefik.yml`, replace the default
`dynamic/proxmox.yml` provider filename with the commented `dynamic/pbs.yml`
alternative, then copy `dynamic/pbs.yml.template` to `dynamic/pbs.yml`. Set the
Let’s Encrypt email and the two PBS names. The PBS template uses port 8007.

For PVE, the static template already selects `dynamic/proxmox.yml`; create its dynamic route using
the required PVE names. Point its service at `https://127.0.0.1:8006`. noVNC
requires no additional Traefik configuration; retain the PVE TCP/3128 firewall
rule separately if SPICE is needed.

Install the verified upstream binary, then provision the service files:

```sh
install -d -m 0700 /var/lib/traefik /etc/traefik/credentials
install -m 0600 traefik.env.template /etc/traefik/traefik.env
install -m 0644 traefik.service /etc/systemd/system/traefik.service
systemctl daemon-reload
```

Create a Cloudflare token with `Zone / Zone / Read` and `Zone / DNS / Edit` for
every certificate zone. Store it outside the repository:

```sh
read -rsp 'Cloudflare DNS API token: ' CF_TOKEN; echo
printf '%s' "$CF_TOKEN" > /etc/traefik/credentials/cloudflare-dns-api-token
unset CF_TOKEN
chmod 0600 /etc/traefik/credentials/cloudflare-dns-api-token
systemctl enable --now traefik
```

DNS-01 supports private A and AAAA records as long as Cloudflare is
authoritative for the DNS zone and can create `_acme-challenge` TXT records.

## Verification

```sh
systemctl is-enabled traefik
systemctl is-active traefik
curl --noproxy '*' -I https://YOUR_PROXMOX_NAME/
openssl s_client -connect YOUR_PROXMOX_NAME:443 -servername YOUR_PROXMOX_NAME </dev/null \
  | openssl x509 -noout -subject -issuer -ext subjectAltName
```

For PBS on this host, both configured names must return the PBS UI through
Traefik and the certificate SAN list must contain both PBS names.
