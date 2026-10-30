# Whisparr

Fleet installs TrueCharts Whisparr chart `15.10.0` in `apps-whisparr`.
The app waits for `whisparr-storage`, which creates a 10Gi Longhorn RWO config
PVC with the existing two-replica StorageClass and NAS backup labels.
One replica uses the Recreate strategy to protect its SQLite database.

The initial 1Gi config volume filled during metadata refresh on 2026-10-30,
causing SQLite disk-full errors followed by disk I/O errors. The requested
capacity was increased to 10Gi; live expansion and application recovery must
be verified after applying the storage bundle.

HTTPS endpoints follow the existing Arr applications:

- https://whisparr.rancher.localdomain.bnowakowski.pl/
- https://whisparr.rancher.tailscale.bnowakowski.pl/

All NFS volumes use `nas.localdomain.bnowakowski.pl`. NAS paths and paths
inside the container are identical:

| Purpose | Path |
| --- | --- |
| Imported movie library / root folder | `/mnt/MargokPool/archive/Movies/nubile` |
| Completed downloads | `/mnt/MargokPool/archive/Movies/Whisparr` |
| Transmission download tree | `/mnt/PlexPool/plex` |

After first startup, configure Whisparr authentication, indexers and download
client credentials in the UI. Select the movie library path as the root folder.
Transmission downloads under `/mnt/PlexPool/plex` are available at the same
path inside Whisparr. The download client must report a path within one of
the mounted download trees; configure a remote path mapping if its container
uses a different path. All NAS exports
must allow the application to read and write. These are separate NFS mounts,
so imports may need a copy rather than hardlinks or an atomic rename.

References:
- https://wiki.servarr.com/whisparr
- https://truecharts.org/charts/stable/whisparr/

Apply only these two new bundles using the Fleet CLI, preserving the existing
`rancher-cluster` ownership and default local-cluster targeting. Before any push,
verify both BundleDeployments applied their desired deployment IDs and have
Ready=True, the config PVC is Bound, the workload is Ready, its rendered NFS
paths match this table, and the HTTPS endpoints respond. Manifest generation
alone is not deployment validation.
