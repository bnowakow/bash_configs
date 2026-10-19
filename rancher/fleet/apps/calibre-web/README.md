# Calibre Web

TrueCharts chart `23.0.1` deploys into `apps-calibre`. Configuration is stored
on a 1Gi local-path PVC at `/config`, supplied by `calibre-storage`. The same export as Ubooquity,
`nas.localdomain.bnowakowski.pl:/mnt/PlexPool/plex/Books`, is mounted at `/books`.

- https://calibre-web.rancher.tailscale.bnowakowski.pl/
- https://calibre-web.rancher.localdomain.bnowakowski.pl/

The `calibre-library` 10Gi local-path PVC is shared with Calibre. It is mounted
read-only at `/library` in Calibre Web and read/write at `/library` in Calibre.
Both run in `apps-calibre` because PVCs cannot be mounted across namespaces.
Local volume node affinity keeps both apps on the same node.

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
