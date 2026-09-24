# TrueNAS app Traefik labels

Reference configuration for exposing TrueNAS Docker apps through the `traefik`
app on the external Docker network named `proxy`.

## Prerequisites

- Traefik and the app share the external `proxy` network, except Syncthing
  (documented below).
- Traefik has a static `letsencrypt` ACME DNS-01 resolver configured.
- DNS resolves the listed hostnames to the NAS on the relevant network.
- Add labels in **Apps > Installed > APP > Edit > Labels Configuration**. In
  scripts, attach every label to the listed application container.

### Create the external proxy network

Run this once on the TrueNAS host. It is safe to rerun: it creates `proxy` only
when the network does not already exist.

```sh
docker network inspect proxy >/dev/null 2>&1 || docker network create --driver bridge --ipv6 proxy
```

Do not use `docker network connect` to attach a TrueNAS-managed app: that change
is lost on the next app redeploy. Add the network through the TrueNAS app update
(`network.networks` in the reusable payload below) instead.

## Traefik additional arguments (currently configured)

Set these in **Traefik Configuration > Additional Arguments**. They are static
Traefik configuration, not Docker labels.

```text
--certificatesresolvers.letsencrypt.acme.email=dobrowolski.nowakowski@gmail.com
--certificatesresolvers.letsencrypt.acme.dnschallenge=true
--certificatesresolvers.letsencrypt.acme.dnschallenge.provider=cloudflare
```

The corresponding Traefik environment variable is:

```text
CF_DNS_API_TOKEN=<Cloudflare DNS API token>
```

All normal applications use these two hostnames:

```text
<app>.nas.tailscale.bnowakowski.pl
<app>.nas.localdomain.bnowakowski.pl
```

## Traefik dashboard (`traefik`)

The installed Traefik app currently enables its built-in dashboard router with
these labels:

```text
traefik.http.routers.app.entrypoints=websecure
traefik.http.routers.app.tls=true
```

To expose the dashboard using the same custom-domain pattern, use a dedicated
router that points to Traefik's internal API service. Replace the two current
dashboard labels above with the following labels (and protect this endpoint
with authentication or a Tailscale ACL before making it broadly reachable):

```text
traefik.enable=true
traefik.http.routers.traefik-dashboard.entrypoints=websecure
traefik.http.routers.traefik-dashboard.rule=Host(`traefik.nas.tailscale.bnowakowski.pl`) || Host(`traefik.nas.localdomain.bnowakowski.pl`)
traefik.http.routers.traefik-dashboard.tls=true
traefik.http.routers.traefik-dashboard.tls.certresolver=letsencrypt
traefik.http.routers.traefik-dashboard.service=api@internal
```

## TrueNAS web interface (`truenas`, HTTPS port `10443`)

TrueNAS itself is a host service, rather than an application container. Add
these labels to the **Traefik** app. The backend must be the NAS LAN address,
not either public hostname, to avoid proxying back into Traefik. TrueNAS's
default backend certificate does not match the LAN IP, so this configuration
keeps TLS to the backend while disabling only its certificate verification. A
`ServersTransport` cannot be defined through Docker labels, so define it in
Traefik's mounted file-provider configuration first:

The tracked file is [`traefik/truenas-transport.yaml`](traefik/truenas-transport.yaml).
Install it on the TrueNAS host before applying the labels:

```sh
install -m 0644 nas/traefik/truenas-transport.yaml \
  /mnt/.ix-apps/app_mounts/traefik/config/truenas-transport.yaml
```

Then add these labels to the **Traefik** app:

```text
traefik.enable=true
traefik.http.routers.truenas.entrypoints=websecure
traefik.http.routers.truenas.rule=Host(`truenas.nas.tailscale.bnowakowski.pl`) || Host(`truenas.nas.localdomain.bnowakowski.pl`)
traefik.http.routers.truenas.tls=true
traefik.http.routers.truenas.tls.certresolver=letsencrypt
traefik.http.routers.truenas.service=truenas
traefik.http.services.truenas.loadbalancer.server.url=https://10.0.0.20:10443
traefik.http.services.truenas.loadbalancer.serverstransport=truenas-insecure@file

# CORS used by requests from the Homer instances.
traefik.http.middlewares.truenas-cors.headers.accesscontrolalloworiginlist=https://homer.rancher.tailscale.bnowakowski.pl,https://homer.rancher.localdomain.bnowakowski.pl
traefik.http.middlewares.truenas-cors.headers.accesscontrolallowmethods=GET,OPTIONS
traefik.http.middlewares.truenas-cors.headers.accesscontrolallowheaders=Authorization,Content-Type
traefik.http.middlewares.truenas-cors.headers.addvaryheader=true
traefik.http.routers.truenas.middlewares=truenas-cors
```

This exposes the UI on port 443 at:

```text
https://truenas.nas.tailscale.bnowakowski.pl/
https://truenas.nas.localdomain.bnowakowski.pl/
```

Ensure both names resolve to the NAS/Traefik listener. Since this is the TrueNAS
administration UI, limit access with a Tailscale ACL or Traefik authentication
before exposing it beyond trusted networks.

## Emby (`emby`, port `8096`)

```text
traefik.enable=true
traefik.http.routers.emby.entrypoints=websecure
traefik.http.routers.emby.rule=Host(`emby.nas.tailscale.bnowakowski.pl`) || Host(`emby.nas.localdomain.bnowakowski.pl`)
traefik.http.routers.emby.tls=true
traefik.http.routers.emby.tls.certresolver=letsencrypt
traefik.http.services.emby.loadbalancer.server.port=8096
```

## Jellyfin (`jellyfin`, port `8096`)

```text
traefik.enable=true
traefik.http.routers.jellyfin.entrypoints=websecure
traefik.http.routers.jellyfin.rule=Host(`jellyfin.nas.tailscale.bnowakowski.pl`) || Host(`jellyfin.nas.localdomain.bnowakowski.pl`)
traefik.http.routers.jellyfin.tls=true
traefik.http.routers.jellyfin.tls.certresolver=letsencrypt
traefik.http.services.jellyfin.loadbalancer.server.port=8096
```

## Scrutiny (`scrutiny`, port `8080`)

Only the web UI is proxied. Do not expose its InfluxDB port `8086` through
Traefik.

```text
traefik.enable=true
traefik.http.routers.scrutiny.entrypoints=websecure
traefik.http.routers.scrutiny.rule=Host(`scrutiny.nas.tailscale.bnowakowski.pl`) || Host(`scrutiny.nas.localdomain.bnowakowski.pl`)
traefik.http.routers.scrutiny.tls=true
traefik.http.routers.scrutiny.tls.certresolver=letsencrypt
traefik.http.services.scrutiny.loadbalancer.server.port=8080

# CORS middleware used only by Scrutiny for requests from the Homer instance.
traefik.http.middlewares.scrutiny-cors.headers.accesscontrolalloworiginlist=https://homer.rancher.tailscale.bnowakowski.pl,https://homer.rancher.localdomain.bnowakowski.pl
traefik.http.middlewares.scrutiny-cors.headers.accesscontrolallowmethods=GET,OPTIONS
traefik.http.middlewares.scrutiny-cors.headers.accesscontrolallowheaders=Authorization,Content-Type
traefik.http.middlewares.scrutiny-cors.headers.addvaryheader=true
traefik.http.routers.scrutiny.middlewares=scrutiny-cors
```

The `scrutiny-cors` middleware is specific to the Scrutiny router and should not
be attached to other application routers.

## MinIO (`minio`)

MinIO needs distinct routers and services for its S3 API and Console.

```text
traefik.enable=true

traefik.http.routers.minio-api.entrypoints=websecure
traefik.http.routers.minio-api.rule=Host(`minio.nas.tailscale.bnowakowski.pl`) || Host(`minio.nas.localdomain.bnowakowski.pl`)
traefik.http.routers.minio-api.tls=true
traefik.http.routers.minio-api.tls.certresolver=letsencrypt
traefik.http.routers.minio-api.service=minio-api
traefik.http.services.minio-api.loadbalancer.server.port=9000

traefik.http.routers.minio-console.entrypoints=websecure
traefik.http.routers.minio-console.rule=Host(`minio-console.nas.tailscale.bnowakowski.pl`) || Host(`minio-console.nas.localdomain.bnowakowski.pl`)
traefik.http.routers.minio-console.tls=true
traefik.http.routers.minio-console.tls.certresolver=letsencrypt
traefik.http.routers.minio-console.service=minio-console
traefik.http.services.minio-console.loadbalancer.server.port=9002
```

## Syncthing (`syncthing`, host network)

Syncthing remains in host-network mode to preserve its direct device-sync and
discovery networking. It must **not** join `proxy`. Traefik reaches only the
web UI through the NAS LAN address and port `20910`.

```text
traefik.enable=true
traefik.http.routers.syncthing.entrypoints=websecure
traefik.http.routers.syncthing.rule=Host(`syncthing.nas.tailscale.bnowakowski.pl`) || Host(`syncthing.nas.localdomain.bnowakowski.pl`)
traefik.http.routers.syncthing.tls=true
traefik.http.routers.syncthing.tls.certresolver=letsencrypt
traefik.http.routers.syncthing.service=syncthing
traefik.http.services.syncthing.loadbalancer.server.url=http://10.0.0.20:20910
```

## Reusable TrueNAS app-update shape

For bridge-networked applications, submit `labels` and `network.networks` in
the app update values. The app container name is usually the app name.

```json
{
  "values": {
    "labels": [
      {"containers": ["APP"], "key": "traefik.enable", "value": "true"}
    ],
    "network": {
      "networks": [
        {
          "name": "proxy",
          "containers": [
            {
              "name": "APP",
              "config": {
                "aliases": [],
                "interface_name": "",
                "mac_address": "",
                "ipv4_address": "",
                "ipv6_address": "",
                "gw_priority": null,
                "priority": null
              }
            }
          ]
        }
      ]
    }
  }
}
```

`traefik.docker.network=proxy` is optional when the target app is attached
only to `proxy`; use it if an app is deliberately connected to multiple Docker
networks.
