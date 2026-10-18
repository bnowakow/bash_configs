# Model B — Proxmox VE with the existing K3s Traefik

This is the **K3s deployment model**. For a Proxmox VE-only or PBS host with
no K3s ingress, use the native systemd Traefik instructions in
`PROXMOX_VE_TRAEFIK_INSTALL.md` instead.

The example configuration is [`pve-proxy.yaml`](pve-proxy.yaml). K3s Traefik
continues to own ports 80 and 443; do not start the native `traefik.service` on
this node.

The route accepts these existing DNS names and forwards only their HTTPS
traffic to PVE's native listener at `10.0.0.72:8006`:

- `proxmox2-old.localdomain.bnowakowski.pl`
- `proxmox2-old.tailscale.bnowakowski.pl`

The `/api2/` path has a dedicated CORS middleware allowing `GET` and `OPTIONS` from `https://homer.rancher.tailscale.bnowakowski.pl` and `https://homer.rancher.localdomain.bnowakowski.pl`, with the `Authorization` and `Content-Type` request headers.

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

## Future handover on proxmox5

The manifest currently describes another host (`proxmox2-old`, `10.0.0.72`);
do not apply it unchanged on proxmox5.

1. Prepare K3s with its bundled Traefik disabled (`--disable=traefik`) while
   the native service still owns ports 80/443.
2. Adapt `pve-proxy.yaml`: replace both `proxmox2-old` names with `proxmox5`
   and replace `10.0.0.72` with `10.0.0.80`. Kubernetes must reach the host LAN
   address; pod loopback does not reach PVE.
3. Prepare cert-manager, a Cloudflare DNS-01 `letsencrypt` ClusterIssuer,
   and its solver selectors for both proxmox5 names. Wait for the `pve-ui`
   Certificate to become Ready before switching traffic.
4. Stop and disable the native service: `systemctl disable --now traefik`.
5. Enable/install K3s Traefik using the cluster's managed configuration,
   then apply the adapted route once its CRDs exist. Verify both names,
   noVNC, and any application routes. Keep TCP/3128 separately protected.

Only one ingress may own host ports 80/443. Keep native configuration and
ACME state for rollback. To roll back, disable K3s Traefik/ServiceLB exposure
and confirm its port forwarding is removed before running
`systemctl enable --now traefik`. Do not run two ACME clients against the same
`acme.json`; cert-manager uses Kubernetes Secrets instead.
