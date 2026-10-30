# Recurring media access incident — 2026-10-30

Status: investigated with restricted host access; recovery not performed or
verified. User reports this is the second occurrence affecting Emby and Nubile.
The date and cause of the first occurrence were not available.

## Evidence

- `compose.yaml`: Emby bind-mounts host `/mnt/PlexPool/plex` at the same
  container path. Nubile uses external Docker NFS volume `nubile_movies`,
  mounted at `/mnt/MargokPool/archive/Movies`.
- Both exports resolve in the current mount table to NAS `10.0.0.20`, client
  `10.0.0.50`. Emby's visible host mount uses NFS 4.2; Nubile's Docker volume
  uses NFS 4.0. A mount-table entry alone does not prove readable media.
- `config/logs/embyserver.txt`, 2026-10-30 08:05:02 (application log time):
  `DirectoryNotFoundException` for Movies and all seven other configured
  library directories under `/mnt/PlexPool/plex`.
- The rotated Emby log `config/logs/embyserver-63928915200.txt` also contains
  missing-library errors. This establishes earlier symptoms, not their cause.
- During inspection, listing `/mnt/PlexPool/plex` and statting its Movies
  directory succeeded from this session. The NAS export is accessible here;
  the container may still see a different or obsolete mount.
- Nubile's current server log contains no matching missing-directory or
  access-denied exception. Its FFmpeg log
  `nubile-config/logs/ffmpeg-transcode-a33a9e0f-4cd2-4915-bddf-b7a8d8fa5cbe_1.txt`
  records media input from its configured NFS path and sustained transcoding
  progress at 09:43–09:45 (application log time). Nubile could read at least
  that file then; a continuous outage of both services is not established.
- No stale-file-handle, NFS I/O error, or permission-denied cause was confirmed
  in the application logs inspected.

## Assessment

Emby's missing paths despite a currently readable host export are consistent
with a container retaining an old mount, or starting before the host NFS mount
was available. These are hypotheses until host/container mount views and
startup timestamps are compared. Ordinary Docker bind mounts do not acquire a
replacement host mount automatically with private propagation.

Nubile uses a separate Docker-managed NFS mount, so Emby's bind-mount hypothesis
does not by itself explain Nubile's reported failure. Check its current mount
and application-user access separately. Do not change NAS permissions based
only on this report: neither a NAS ACL failure nor a common NAS outage has been
demonstrated.

The scheduled upgrade runs at 04:30 and can recreate containers, but its log
was unreadable here. There is no evidence yet linking an upgrade to this incident.

## Access limitation

`docker compose ps` failed with permission denied on `/var/run/docker.sock`.
`sudo -n docker compose ps` failed because this session has `no new privileges`
and sudo also reports unmapped ownership of `/etc/sudo.conf`. The session maps
only host UID/GID 1000 and cannot inspect Docker's volume directory or kernel
logs. Those restrictions are not evidence of the Emby process's permissions.
The host path `/mnt/MargokPool/archive/Movies` need not exist: Nubile's export
is mounted inside Docker's volume directory.

## Verification on proxmox3

Run from this directory in a host shell with Docker/root access. Capture these
results before restarting so the failing mount state is preserved:

```sh
docker compose ps
docker inspect emby nubile --format '{{.Name}} started={{.State.StartedAt}} mounts={{json .Mounts}}'
docker volume inspect nubile_movies
findmnt -T /mnt/PlexPool/plex
findmnt -T /var/lib/docker/volumes/nubile_movies/_data
ls -ld /mnt/PlexPool/plex/Movies
ls -ld /var/lib/docker/volumes/nubile_movies/_data/nubile
docker compose exec -T emby sh -c 'ls -ld /mnt/PlexPool/plex /mnt/PlexPool/plex/Movies; cat /proc/self/mountinfo'
docker compose exec -T nubile sh -c 'ls -ld /mnt/MargokPool/archive/Movies /mnt/MargokPool/archive/Movies/nubile; cat /proc/self/mountinfo'
docker compose logs --since 24h --tail 200 emby nubile
journalctl -k --since '2026-10-28' --no-pager
cat /var/log/emby-upgrade.log
```

Also inspect the running Emby process's UID, GID and supplementary groups in
each container (`/proc/<Emby-process-pid>/status`); a default root `exec` succeeding
does not prove application-user access. Compose requests UID/GID 568 and includes
group 1000 specifically for Nubile's Movies permissions. Verify a known media
file can be opened as that process identity, then test playback in each UI.

## Conditional recovery

If the host export is readable but Emby's container is missing its libraries,
recreate Emby to establish a fresh bind mount (brief playback interruption):

```sh
docker compose up -d --force-recreate --no-deps emby
docker compose exec -T emby ls -ld /mnt/PlexPool/plex/Movies
```

For Nubile, if its Docker volume is readable on the host but absent/broken in
the container, recreate only Nubile and recheck:

```sh
docker compose up -d --force-recreate --no-deps nubile
docker compose exec -T nubile ls -ld /mnt/MargokPool/archive/Movies/nubile
```

Recreation may not repair an unhealthy Docker volume mount. If the host-side
volume itself hangs or fails, first diagnose NAS export availability and kernel
NFS errors. Stop its consumers before repairing that mount. Do not delete the
external volume or lazily unmount exports shared with other workloads.
After recovery, verify playback and a library scan, and record the results below.

## Recurrence prevention to implement after confirmation

- If startup order is confirmed, gate Compose startup on the actual Emby NFS
  mount and successful access to an expected library directory. A systemd unit
  can use `RequiresMountsFor=/mnt/PlexPool/plex`; also check readability before
  starting/recreating services, including in `upgrade.sh`.
- `bind.create_host_path: false` prevents creation of a missing source directory
  but cannot detect an existing directory whose NFS filesystem is not mounted.
- Monitor expected media directories from inside each container. Current
  `restart: unless-stopped` and upgrade `--wait` do not establish media health;
  there is no application/media healthcheck in Compose.
- Record NAS/client reboot and remount times alongside container start times
  on the next occurrence. Preserve evidence before recovery.

## Recovery record

Pending host-level verification. No Compose settings, permissions, mounts,
containers, or library contents were changed during this investigation.

## Handoff to the next Codex session

The user requested a fix and will start the next Codex session with sudo access.
Continue diagnosis and recovery from this document in
`/home/sup/code/bash_configs/proxmox/emby` on proxmox3. The fix remains pending;
the recovery commands above have **not** been executed.

A second access check after the fix request returned the same Docker socket
permission denial and sudo `no new privileges` failure. No privileged host
management tool was available in this session. Starting a session with working
host sudo/root access is required; retrying sudo inside the current restricted
session does not resolve this.

Next steps:

1. Verify `sudo -n docker compose ps` works (or use Docker directly as root).
   Capture the verification commands above before any restart. Inspect actual
   container mounts, application process identities, kernel NFS errors and the
   04:30 upgrade log to establish the cause.
2. Compare host and container access separately for both services. Emby's
   missing-directory errors are confirmed; Nubile's reported outage still needs
   current verification because its recent FFmpeg log shows successful reads.
3. If the host Plex export is readable and only Emby's container mount is
   broken, recreate Emby using the conditional recovery above. Recreate Nubile
   only if its checks establish the same need. Expect a brief playback
   interruption for each recreated service.
4. Verify expected library directories and a media-file read using each
   running application's UID/GID and supplementary groups, then playback and
   library scanning. Root-only directory listings are insufficient.
5. Implement recurrence prevention appropriate to the confirmed cause. Update
   this file with evidence, exact changes, recovery time and validation results.

The user has requested diagnosis and repair; the current blocker is execution
access. Avoid treating the mount/startup hypotheses as an established root cause
or recording either service as fixed until verified.
