# Emby and Nubile

One Compose project runs two independent Emby servers on proxmox3. YAML anchors
share image, restart policy, GPU devices and runtime IDs. Each instance retains
its own users, settings, databases, media mount and published port.

| Service | Private config | Host port | Media |
| --- | --- | --- | --- |
| emby | `./config` | 8096 | Host NFS bind `/mnt/PlexPool/plex` |
| nubile | `./nubile-config` | 8097 | NFS `nas.localdomain.bnowakowski.pl:/mnt/MargokPool/archive/Movies` |

Both use `/dev/dri` and UID/GID 568. Nubile also has group 1000 for Movies
permissions (1000:1000, mode 770). Both config directories are ignored by Git.
The external Docker NFS volume `nubile_movies` is reused without copying media.
For recurring missing-media symptoms, evidence and recovery steps are recorded
in [NFS-incident.md](NFS-incident.md).
On a new host, create it before starting:

```sh
docker volume create --driver local --opt type=nfs --opt o=addr=nas.localdomain.bnowakowski.pl,rw,nfsvers=4 --opt device=:/mnt/MargokPool/archive/Movies nubile_movies
```

From the repository root:

```sh
docker compose -f proxmox/emby/compose.yaml up -d
docker compose -f proxmox/emby/compose.yaml logs --tail=100 emby
docker compose -f proxmox/emby/compose.yaml logs --tail=100 nubile
```

Append a service name to `up -d` to manage one instance. The old
`emby-tmp-for-encoding` and `nubile` projects have been retired. Configuration
was moved while both instances were stopped. Historical transcoding comparison
results are retained in `summary.md` and `summary.html`.

Existing Fleet ingress bundles and URLs remain:

- https://emby.proxmox3.localdomain.bnowakowski.pl/
- https://emby.proxmox3.tailscale.bnowakowski.pl/
- https://nubile.proxmox3.localdomain.bnowakowski.pl/
- https://nubile.proxmox3.tailscale.bnowakowski.pl/

## Image updates

Run `make` in this directory for help. `make upgrade` checks the configured
image tags and updates both services if needed. It downloads images before
recreating containers, preserves configuration and media mounts, and prevents
overlapping upgrades. Updates briefly interrupt playback. Compose waits for
containers to run; the services currently have no application healthcheck.

`make install-cron` installs an idempotent root cron job in
`/etc/cron.d/emby-upgrade`, scheduled daily at 04:30 host local time. The job calls
the same `upgrade.sh` as `make upgrade`. Installation requires sudo. Output is
written to `/var/log/emby-upgrade.log`, with weekly log rotation.
