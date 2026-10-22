# Kavita

TrueCharts Kavita chart `14.0.3` runs in `apps-calibre` and depends on
`calibre-storage`. It has its own 1Gi local-path config PVC mounted at `/config`.

- https://kavita.rancher.tailscale.bnowakowski.pl/
- https://kavita.rancher.localdomain.bnowakowski.pl/

Traefik serves both hosts over HTTPS with the `letsencrypt` certificate issuer.

The NAS export `nas.localdomain.bnowakowski.pl:/mnt/PlexPool/plex/Books` is
mounted at `/books`, matching Calibre and Ubooquity. The `calibre-library` PVC
is mounted read-only at `/library`, matching Calibre Web. The shared PVC
requires the same namespace and its local volume node affinity keeps Kavita
on the storage node. The chart's default `/manga` volume is disabled.

Create the initial administrator account in the Kavita UI, then add libraries
using `/books` and/or `/library`. Kavita scans the book files; it does not use
Calibre Web's `metadata.db` configuration. Manage the shared Calibre library
through Calibre; Kavita cannot write to its read-only mount.
