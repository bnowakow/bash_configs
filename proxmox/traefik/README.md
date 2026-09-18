# Traefik for this Proxmox host

Traefik terminates TLS on ports 80/443 and forwards the PVE UI to
`https://127.0.0.1:8006`. The deployed names are `proxmox4.localdomain.bnowakowski.pl` and `proxmox4.tailscale.bnowakowski.pl`; one DNS-01 Let’s Encrypt certificate covers both.

`noVNC` needs no additional routing: Traefik forwards WebSocket upgrades.
External `remote-viewer` SPICE remains PVE's own plain HTTP CONNECT service on
port 3128. It is deliberately not tunneled through HTTPS/443; requests made to
the PVE UI via either configured hostname produce a `.vv` file that uses that
same hostname on port 3128.

## Deployed version and updates

The deployed service uses the checksum-verified upstream `linux/amd64` Traefik `v3.7.13` binary at `/usr/local/bin/traefik`. The configured Debian Trixie and Proxmox APT repositories have no `traefik` package, so APT will not update it. Use the pinned-release update procedure in `PROXMOX_VE_TRAEFIK_INSTALL.md`, then restart and verify the service.

## Tracked versus local files

`*.template` files are safe to commit. `traefik.yml` and
`dynamic/proxmox.yml` are ignored because the live static configuration contains
the ACME contact email. `/var/lib/traefik/acme.json` is never committed: it
contains ACME private keys and certificates.

## Initial secret provisioning

Do not put the Cloudflare token in this repository or shell history. Provision
it on the host as root, then start Traefik:

```sh
install -d -m 0700 /etc/traefik/credentials
read -rsp 'Cloudflare DNS API token: ' CF_TOKEN; echo
printf '%s' "$CF_TOKEN" > /etc/traefik/credentials/cloudflare-dns-api-token
unset CF_TOKEN
chmod 0600 /etc/traefik/credentials/cloudflare-dns-api-token
systemctl enable --now traefik
```

The token needs `Zone / Zone / Read` and `Zone / DNS / Edit` on both Cloudflare
zones. Traefik receives the token via `CF_DNS_API_TOKEN_FILE`.

## SPICE restriction

The host currently has no active PVE firewall. Before treating SPICE as usable
from an untrusted LAN, add an equivalent firewall allow-list for TCP/3128.
Traefik's HTTP allow-list protects 443, but cannot protect the PVE-owned 3128
listener.
