# Proxmox VE access through Traefik

This note records a tested configuration for exposing the Proxmox web UI on
HTTPS/443 without breaking noVNC. It also covers the SPICE client connection.

## Important: check port ownership first

Before installing a native Traefik service, run:

```sh
ss -ltnp '( sport = :80 or sport = :443 )'
iptables-save -t nat | rg -C 3 -- '--dport (80|443)'
```

On a K3s node, ServiceLB can own hostPorts 80 and 443 and redirect them
to the Kubernetes Traefik service. A native process can bind the ports but will
not receive the packets. Do **not** install native Traefik on a K3s node with
that mapping unless ServiceLB is deliberately moved away from that node.

For a non-K3s host, continue with the native installation below.

## Native Traefik installation (non-K3s host)

The files in this directory are the source of truth:

- Commit the templates, `traefik.service`, this document, and `README.md`.
- Do not commit `traefik.yml`, `dynamic/proxmox.yml`, `/etc/traefik/traefik.env`,
  `/etc/traefik/credentials/*`, or `/var/lib/traefik/acme.json`.

Copy `traefik.yml.template` to `traefik.yml`, set the Let’s Encrypt email, and
copy `dynamic/proxmox.yml.template` to `dynamic/proxmox.yml`. Replace both
hostnames and adjust the LAN/Tailscale ranges if necessary. The deployed names are `proxmox4.localdomain.bnowakowski.pl` and `proxmox4.tailscale.bnowakowski.pl`.

This host runs the checksum-verified upstream `linux/amd64` Traefik `v3.7.13` binary at `/usr/local/bin/traefik`. Its configured Debian Trixie and Proxmox APT repositories provide no `traefik` package, so it is not updated by APT. For an update, obtain the release checksum from the official GitHub release, verify the downloaded archive, replace `/usr/local/bin/traefik`, then run `systemctl restart traefik` and the verification commands below.

Install a pinned official Traefik release, verify the release checksum, and
install the systemd unit:

```sh
install -d -m 0700 /var/lib/traefik /etc/traefik/credentials
install -m 0600 traefik.env.template /etc/traefik/traefik.env
install -m 0644 traefik.service /etc/systemd/system/traefik.service
systemctl daemon-reload
```

Create a Cloudflare API token with only `Zone / Zone / Read` and
`Zone / DNS / Edit`, scoped to every DNS zone used by the certificate. Put it
outside the repository:

```sh
read -rsp 'Cloudflare DNS API token: ' CF_TOKEN; echo
printf '%s' "$CF_TOKEN" > /etc/traefik/credentials/cloudflare-dns-api-token
unset CF_TOKEN
chmod 0600 /etc/traefik/credentials/cloudflare-dns-api-token
systemctl enable --now traefik
```

Verify both names directly after startup:

```sh
curl --noproxy '*' -I https://YOUR_PVE_NAME/
openssl s_client -connect YOUR_PVE_NAME:443 -servername YOUR_PVE_NAME </dev/null \
  | openssl x509 -noout -subject -issuer -ext subjectAltName
```

DNS-01 supports private names: the A/AAAA record does not need to be reachable
from the public Internet, but Cloudflare must be authoritative for the DNS zone
and Traefik must be able to create `_acme-challenge` TXT records.

### noVNC and SPICE

noVNC works through the HTTPS router without special configuration; Traefik
proxies WebSocket upgrades automatically.

SPICE `remote-viewer` is different. PVE emits a `.vv` file pointing to
`http://<the-UI-hostname>:3128`. Keep `spiceproxy.service` running and permit
TCP/3128 from the same trusted LAN/Tailnet clients. Do not attempt to put this
plain HTTP CONNECT proxy behind HTTPS/443. Protect direct PVE 8006 and SPICE
3128 with the PVE firewall or equivalent host firewall.

## Existing K3s Traefik: preferred approach

If K3s already exposes port 80/443, add the PVE route to that Traefik instance;
do not run a competing native listener. On this cluster, cert-manager and the
Traefik CRDs are already installed, and the `letsencrypt` ClusterIssuer is
Ready. Use cert-manager for the certificate rather than altering Traefik's
global ACME configuration.

Create a dedicated namespace and a selectorless Service plus EndpointSlice for
the PVE host. Replace the addresses and names below.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: pve-proxy
---
apiVersion: v1
kind: Service
metadata:
  name: pve-api
  namespace: pve-proxy
spec:
  ports:
    - name: https
      port: 8006
      protocol: TCP
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: pve-api-ipv4
  namespace: pve-proxy
  labels:
    kubernetes.io/service-name: pve-api
addressType: IPv4
ports:
  - name: https
    protocol: TCP
    port: 8006
endpoints:
  - addresses: ["PVE_LAN_IP"]
---
apiVersion: traefik.io/v1alpha1
kind: ServersTransport
metadata:
  name: pve-backend
  namespace: pve-proxy
spec:
  insecureSkipVerify: true
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: pve-ui
  namespace: pve-proxy
spec:
  secretName: pve-ui-tls
  issuerRef:
    kind: ClusterIssuer
    name: letsencrypt
  dnsNames:
    - PVE_LAN_FQDN
    - PVE_TAILSCALE_FQDN
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: pve-ui
  namespace: pve-proxy
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`PVE_LAN_FQDN`) || Host(`PVE_TAILSCALE_FQDN`)
      kind: Rule
      services:
        - name: pve-api
          port: 8006
          scheme: https
          serversTransport: pve-backend
  tls:
    secretName: pve-ui-tls
```

The referenced `ClusterIssuer` must use Cloudflare DNS-01. If the existing
`letsencrypt` issuer is not Cloudflare-backed or lacks access to both zones,
create a separate issuer and use that name in `issuerRef`. Store the Cloudflare
token only in a Kubernetes Secret. The stock K3s Traefik already forwards
WebSockets, so noVNC works. SPICE still goes directly to PVE TCP/3128.

Apply only after reviewing the substituted values:

```sh
kubectl apply -f pve-proxy.yaml
kubectl -n pve-proxy get certificate,ingressroute,serversTransport,endpointslice
```
