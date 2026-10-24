# Calibre

TrueCharts chart `21.1.0` installs the Calibre desktop in `apps-calibre`.
Settings persist on the 256Mi Longhorn RWO `calibre-config-longhorn-rwo` PVC at `/config`. The shared NAS export
`nas.localdomain.bnowakowski.pl:/mnt/PlexPool/plex/Books` is mounted at `/books`.

Browser desktop:

- https://calibre.rancher.tailscale.bnowakowski.pl/
- https://calibre.rancher.localdomain.bnowakowski.pl/

The `longhorn-calibre-arr-storage` Fleet bundle provides a dedicated 1Gi Longhorn RWO PVC,
`calibre-library-longhorn-rwo`, mounted read/write at `/library`. Use the desktop setup to
create a library at `/library`, then import ebooks from `/books`. Calibre manages its own book folders and
`metadata.db` inside the library. This deployment does not automatically import
or reorganize existing ebooks.

Calibre Web runs in the same namespace and mounts this PVC read-only at
`/library`. In Calibre Web, select `/library` after `/library/metadata.db` exists.
Calibre, Calibre Web, Kavita and maintenance share explicit proxmox2-old placement
for the shared RWO volume; changing hosts requires a coordinated group move.
Back up the library separately; it is not stored on the NAS.
Calibre is already present in the shared TrueCharts Helm upgrade mapping.
