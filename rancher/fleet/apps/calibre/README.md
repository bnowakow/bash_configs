# Calibre

TrueCharts chart `21.0.1` installs the Calibre desktop in `apps-calibre`.
Settings persist on a 1Gi local-path PVC at `/config`. The shared NAS export
`nas.localdomain.bnowakowski.pl:/mnt/PlexPool/plex/Books` is mounted at `/books`.

Browser desktop:

- https://calibre.rancher.tailscale.bnowakowski.pl/
- https://calibre.rancher.localdomain.bnowakowski.pl/

The `calibre-storage` Fleet bundle provides a dedicated 10Gi local-path PVC,
`calibre-library`, mounted read/write at `/library`. Use the desktop setup to
create a library at `/library`, then import ebooks from `/books`. Calibre manages its own book folders and
`metadata.db` inside the library. This deployment does not automatically import
or reorganize existing ebooks.

Calibre Web runs in the same namespace and mounts this PVC read-only at
`/library`. In Calibre Web, select `/library` after `/library/metadata.db` exists.
The library and both apps are constrained to the local volumes' node.
Back up the library separately; it is not stored on the NAS.
Calibre is already present in the shared TrueCharts Helm upgrade mapping.
