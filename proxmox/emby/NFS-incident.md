# Recurring Emby media access incident

Status: **root cause confirmed and fixed 2026-11-01** (investigated as root on
proxmox3). Fix: option 2 below plus media healthchecks. See "Fix applied".

## Summary

Only the `emby` service is affected. After each host boot, Docker starts the
`emby` container **before** systemd mounts the NFS share `/mnt/PlexPool/plex`
from `/etc/fstab`. The bind mount therefore captures the empty local directory
on the ZFS root filesystem. When NFS mounts on the host about 6 s later, the
container cannot see it, because the bind uses `rprivate` propagation. Emby
then reports `DirectoryNotFoundException` for every library until the container
is recreated.

The NAS, the network and NFS itself are fine: the host mount works, and the
kernel log has no NFS errors. `nubile` is not affected. Its media is a
Docker-managed NFS volume (`nubile_movies`), which Docker mounts itself when
the container starts. It cannot capture an unmounted directory.

Symptoms come and go because a container recreate fixes the mount until the
next reboot. A manual recreate, or `upgrade.sh` recreating containers when a new
image is published, makes media visible again. The next host reboot reproduces
the race.

## Evidence

Container mount view (`/proc/self/mountinfo`), current boot:

```
emby:   /mnt/PlexPool/plex ... - zfs rpool/ROOT/pve-1          <- local dir, NOT NFS
nubile: /mnt/MargokPool/archive/Movies ... - nfs4 :/mnt/MargokPool/archive/Movies vers=4.0
```

On the host, `findmnt /mnt/PlexPool/plex` shows the correct
`nfs4 nas.localdomain.bnowakowski.pl:/mnt/PlexPool/plex vers=4.2`. Inside
`emby`, `ls /mnt/PlexPool/plex` is empty and `Movies` does not exist. Inside
`nubile`, the Movies share lists normally (owner 1000:1000).

Boot timeline, current boot (`journalctl -b -o short-precise`):

| Time (CET) | Event |
| --- | --- |
| 21:21:58.756 | `network-online.target` reached |
| 21:21:58.855 | `Mounting mnt-PlexPool-plex.mount` |
| 21:21:58.935 | `Starting docker.service` |
| 21:21:59.703 | **emby container started** (`f61e35380d89`) |
| 21:22:04.846 | nubile's NFS volume mounted by Docker (nfsrahead) |
| 21:22:04.910 | nubile container started |
| 21:22:05.736 | **`Mounted mnt-PlexPool-plex.mount`**, 6 s after emby started |
| 21:22:05.737 | `remote-fs.target` reached |

The same order appears in every boot in the journal:

| Boot | docker.service started | Plex NFS mounted |
| --- | --- | --- |
| 2026-10-01 | 11:30:28.6 | 11:30:34.6 |
| 2026-10-07 | 11:55:03.8 | 11:55:09.8 |
| 2026-10-09 | 19:32:25.9 | 19:32:32.0 |
| 2026-10-15 | 10:52:05.7 | 10:52:11.6 |
| 2026-10-19 | 17:02:24.9 | 17:02:31.3 |
| 2026-10-28 | 21:22:05.3 | 21:22:05.7 |

Why systemd allows this:

- `docker.service` is ordered only `After=network-online.target` (plus
  socket/containerd). It has no ordering against `remote-fs.target` or
  `/mnt/PlexPool/plex`.
- The fstab entry (`nfs defaults`) gets ordered before `remote-fs.target`, but
  nothing makes Docker wait for that target.
- `restart: unless-stopped` makes dockerd start the container as soon as the
  daemon is up.

Other checks:

- `journalctl -k` contains no `server not responding`, stale file handle or
  NFS I/O errors. Only module registration messages appear at boot.
- `/var/log/emby-upgrade.log` (2026-11-01 04:30) pulled an unchanged image. It
  left both containers `Running`, so it did not recreate them. The upgrade job
  did not cause this. It repairs the problem only when a new image triggers a
  recreate.
- `docker compose`'s `--wait` reports the containers `Healthy` because they
  have no media healthcheck. A broken mount is not detected.
- Emby logs with `DirectoryNotFoundException` under `/mnt/PlexPool/plex`:
  `embyserver.txt` and rotated logs `-63928915200`, `-63928998427`,
  `-63929088000`, `-63929121740`.
- The earlier note that "the host export is readable but the container may see
  an obsolete mount" was correct. The container sees the underlying local
  directory, not a stale NFS mount.

## Recovery (immediate)

Recreate only Emby, after confirming that the host mount is NFS:

```sh
findmnt -T /mnt/PlexPool/plex          # must show nfs4
docker compose up -d --force-recreate --no-deps emby
docker compose exec -T emby sh -c 'grep PlexPool /proc/self/mountinfo; ls -ld /mnt/PlexPool/plex/Movies'
```

`mountinfo` should now show `nfs4`. Afterwards, run a library scan in the UI.

## Permanent fix options considered

1. **Make Docker wait for the mount (recommended, smallest change).** Add a
   systemd drop-in for `docker.service`:

   ```ini
   # /etc/systemd/system/docker.service.d/wait-for-nfs.conf
   [Unit]
   RequiresMountsFor=/mnt/PlexPool/plex
   ```

   Then run `systemctl daemon-reload`. This adds `Requires=` and `After=` on
   `mnt-PlexPool-plex.mount`. Trade-offs:
   - Docker, including nubile, will not start if the NAS is down at boot.
   - Stopping or unmounting the share also stops Docker.
   - Use `Wants=` + `After=mnt-PlexPool-plex.mount` instead to keep ordering
     without the hard dependency.

   The fix is host configuration outside this directory. Record it in the
   repository if adopted.

2. **Use the same pattern as nubile.** Switch emby to a Docker NFS volume
   (`type=nfs`, `addr=nas...`, `device=:/mnt/PlexPool/plex`). Docker then
   mounts it at container start and can never capture an empty directory.
   This removes the dependency on fstab for emby. The fstab mount stays for
   other host and k8s users.

3. Not recommended alone: `bind.propagation: rslave` would let a later host
   mount propagate into the container. Emby could still scan an empty library
   in the first seconds, and it hides rather than prevents the race.

In addition to any of these, add a Compose healthcheck that tests a known
library directory, for example `test -d /mnt/PlexPool/plex/Movies`. A broken
mount will then show as unhealthy, and `upgrade.sh --wait` will fail loudly.

## Fix applied — 2026-11-01

Option 2 was chosen over option 1. With an NFS volume, Emby no longer depends
on the fstab mount, so ordering Docker after it would add only the coupling
(Docker, and Nubile with it, blocked when the share is unavailable).

Changes in `compose.yaml`:

- `emby` mounts a Compose-managed volume `plex` (Docker name `emby_plex`):
  `type=nfs`, `o=addr=nas.localdomain.bnowakowski.pl,rw,nfsvers=4.2`,
  `device=:/mnt/PlexPool/plex`. It is mounted at the same container path, so
  Emby library paths are unchanged. The host fstab mount stays for other users.
- Both services get a shared healthcheck (`x-media-healthcheck`):
  - Emby tests `/mnt/PlexPool/plex/Movies`.
  - Nubile tests `/mnt/MargokPool/archive/Movies/nubile`.
  - Settings: interval 60s, timeout 10s, retries 3, start period 60s with 5s
    start interval.
  - The healthcheck only reports. Docker does not restart unhealthy containers.
    `upgrade.sh` / `make restart` fail through `--wait`.
- `make restart` added. It force-recreates both services and waits for health.

Remaining risk: if the NAS is unreachable when the host boots, Emby's volume
mount fails and the container stays stopped. Docker's restart policy does not
retry start failures. Nubile has always behaved this way. Start it with
`make restart` once the NAS is back.

Validation after `docker compose up -d --wait`:

- Both containers are `healthy`.
- Emby `/proc/self/mountinfo`:
  `nfs4 nas.localdomain.bnowakowski.pl:/mnt/PlexPool/plex vers=4.2`. All
  library directories are listed.
- As UID/GID 568, Emby read 1 MiB of
  `Movies/Play Dirty (2025)/Play Dirty (2025) WEBDL-2160p.mkv`.
- As 568:1000, Nubile listed `Movies/nubile`.
- No new `DirectoryNotFoundException` in `config/logs/embyserver.txt` after
  the restart.
- `make restart` was run afterwards. Both services came back healthy.

Not yet observed: a full host reboot with the new configuration. On the next
reboot, check `docker compose ps` and Emby's mountinfo (`nfs4` expected).
