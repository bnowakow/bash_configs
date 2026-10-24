# Calibre Web

TrueCharts chart `23.0.4` deploys into `apps-calibre`. Configuration is stored
on the 256Mi Longhorn RWO `calibre-web-config-longhorn-rwo` PVC at `/config`,
supplied by `longhorn-calibre-arr-storage`. The same export as Ubooquity,
`nas.localdomain.bnowakowski.pl:/mnt/PlexPool/plex/Books`, is mounted at `/books`.

- https://calibre-web.rancher.tailscale.bnowakowski.pl/
- https://calibre-web.rancher.localdomain.bnowakowski.pl/

The `calibre-library-longhorn-rwo` 1Gi Longhorn RWO PVC is shared with Calibre. It is mounted
read-only at `/library` in Calibre Web and read/write at `/library` in Calibre.
Both run in `apps-calibre` because PVCs cannot be mounted across namespaces.
Explicit proxmox2-old selectors keep Calibre, Calibre Web, Kavita and maintenance
on the same node for shared RWO access; coordinated placement changes are required.

Create a Calibre library at `/library` through the Calibre desktop and import
books from `/books`. Once `/library/metadata.db` exists, select `/library` in
Calibre Web's database configuration. The full library, including book files,
must live on this PVC. Calibre Web cannot modify the shared library, so editing,
uploading, and deleting library content must be done in Calibre.

Calibre Web was migrated from `apps-calibre-web` with its existing account
and settings databases preserved. The old Helm release was removed after the
restored database passed its integrity check. No existing ebooks were imported
or reorganized as part of this move.

Default upstream login is `admin` / `admin123`; change it after signing in.
See https://github.com/janeczku/calibre-web#quick-start for database setup.

## Covers and thumbnails

The `calibre-cover-maintenance` Fleet bundle extracts missing embedded covers
and refreshes thumbnails daily at 03:00 Europe/Warsaw. Both the web deployment
and Job use the persistent `/config/thumbnail-cache` directory.
See [maintenance details](../calibre-cover-maintenance/README.md).

Keep split-library mode disabled: both the Calibre database and its managed
book/cover files are in `/library`. `/books` is the separate NAS import source.
An earlier split-library setting pointed file lookups at `/books`, causing
missing cover errors even though `/library` contained valid covers.
