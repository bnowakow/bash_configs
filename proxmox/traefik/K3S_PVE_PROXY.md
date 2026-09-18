# Model B — Proxmox VE with the existing K3s Traefik

This is the **K3s deployment model**. For a Proxmox VE-only or PBS host with
no K3s ingress, use the native systemd Traefik instructions in
`PROXMOX_VE_TRAEFIK_INSTALL.md` instead.

The live configuration is [`pve-proxy.yaml`](pve-proxy.yaml). K3s Traefik
continues to own ports 80 and 443; do not start the native `traefik.service` on
this node.

The route accepts these existing DNS names and forwards only their HTTPS
traffic to PVE's native listener at `10.0.0.72:8006`:

- `proxmox2-old.localdomain.bnowakowski.pl`
- `proxmox2-old.tailscale.bnowakowski.pl`

It uses a selectorless Service and EndpointSlice, so no PVE workload is added
to Kubernetes. The `ServersTransport` accepts PVE's private backend
certificate; the client-facing certificate is managed by cert-manager and the
shared `letsencrypt` ClusterIssuer.

The issuer's Cloudflare DNS-01 solver selector must include both names above.
When moving this route to another hostname, update both `pve-proxy.yaml` and
that selector before applying the manifest:

```sh
kubectl apply -f pve-proxy.yaml
kubectl -n pve-proxy get certificate,ingressroute,serversTransport,endpointslice
```

noVNC works through this route because Traefik forwards WebSocket upgrades.
SPICE is separate: PVE clients connect directly to TCP/3128, which must be
firewall-restricted to trusted LAN/Tailnet sources.
