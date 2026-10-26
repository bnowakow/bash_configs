# Migrated local-path storage reclamation — 2026-10-26

## Result at 17:50 CET

The user authorized removing migrated local-path claims that are no longer in
use and have Longhorn replacements. The inventory found 39 such source PVCs:
28 on proxmox3 and 11 on proxmox2-old. Mailpile's two local-path claims remain
in use and were excluded.

On proxmox3, the 28 old data directories, PVCs and Retain PV objects were
removed. The source directories totaled **8,865,227 KiB (~8.46GiB) apparent
usage**. ZFS `rpool` reported 155GiB allocated / 317GiB free before cleanup and
146GiB allocated / 326GiB free afterward. The pool values are rounded; this is
not an exact allocation delta. Mailserver remained Ready 1/1, and Longhorn
applications continue using their target claims.

The removed claims were AdGuard Home (2), Bazarr, Bindery, BookStack (2),
Cleanuparr, ddclient, DuckDNS, Filebot (3), FlareSolverr, Homer (2),
Jellyseerr, Profilarr, Prowlarr, Radarr, Scrutiny (2), SmokePing (2), Sonarr,
youtube-dl Material (3), and Zabbix. Each source PV was node-pinned to proxmox3;
its exact host path was checked as an ordinary non-mounted directory, and the
matching Longhorn claim existed. The active Deployment/StatefulSet templates
used Longhorn claims. Longhorn volumes were healthy with two replicas except
Filebot's three detached targets; Filebot's completed migration record reports
verified copy checks and completed NAS backups. Three completed migration Job
pods (Bazarr, Filebot and Scrutiny) were removed because PVC-protection
finalizers held their source claims. Migration results remain recorded in
their respective `longhorn/migrations/*/RESULTS.md` files.

## Still outstanding

Eleven unused migrated source PVCs remain on proxmox2-old:

- Audiobookshelf: `audiobookshelf-config`, `audiobookshelf-metadata`
- Authelia: `authelia-config`
- Calibre group: `calibre-config`, `calibre-library`, `calibre-web-config`, `kavita-config`
- OpenBooks: `openbooks-books`, `openbooks-logs`
- Ubooquity: `ubooquity-config`
- Uptime Kuma: `uptime-kuma-config`

Their active workload templates use Longhorn claims, which are Bound and
healthy with two replicas. Their original PVs are still Bound to local-path
directories on proxmox2-old. No peer PVC, PV or directory was changed during
this cleanup. SSH from proxmox3 to `proxmox2-old.tailscale.bnowakowski.pl`
failed host-key verification; the host is absent from the available
`known_hosts` files. Do not bypass SSH host-key verification. Reclaim the 11
peer directories and release their PVC/PV records after a trusted host key is
available.

Mailpile's two source claims (`mailpile-path1`, `mailpile-path2`) are still
mounted by the running Mailpile Deployment and were deliberately left alone.

## proxmox2-old local reclamation runbook

Run these steps **on proxmox2-old as root**, after confirming the Longhorn
replacements remain healthy. This is intentionally a local procedure; do not
disable SSH host-key checking to run it remotely. The source PV reclaim policy
is `Retain`, so deleting a source PVC releases its PV but does not remove the
host directory. The directory removal below is the data deletion step.

### Exact source-to-target inventory

| Namespace / source PVC | Longhorn replacement PVC | Source PV | Source directory |
| --- | --- | --- | --- |
| `apps-audiobookshelf/audiobookshelf-config` | `audiobookshelf-config-longhorn-rwo` | `pvc-73a215bd-653b-44bf-8eb6-60256c5bc919` | `/var/lib/rancher/k3s/storage/pvc-73a215bd-653b-44bf-8eb6-60256c5bc919_apps-audiobookshelf_audiobookshelf-config` |
| `apps-audiobookshelf/audiobookshelf-metadata` | `audiobookshelf-metadata-longhorn-rwo` | `pvc-79543895-5f34-4245-b3d4-1e9c716b80a1` | `/var/lib/rancher/k3s/storage/pvc-79543895-5f34-4245-b3d4-1e9c716b80a1_apps-audiobookshelf_audiobookshelf-metadata` |
| `apps-authelia/authelia-config` | `authelia-config-longhorn-rwo` | `pvc-7b0f9244-8283-4122-8579-ba55bf3cc754` | `/var/lib/rancher/k3s/storage/pvc-7b0f9244-8283-4122-8579-ba55bf3cc754_apps-authelia_authelia-config` |
| `apps-calibre/calibre-config` | `calibre-config-longhorn-rwo` | `pvc-dfa615ad-2056-4ba5-854f-a5fe6ea6d28e` | `/var/lib/rancher/k3s/storage/pvc-dfa615ad-2056-4ba5-854f-a5fe6ea6d28e_apps-calibre_calibre-config` |
| `apps-calibre/calibre-library` | `calibre-library-longhorn-rwo` | `pvc-877a9cbc-3dd6-44c8-8036-38ed301ebf78` | `/var/lib/rancher/k3s/storage/pvc-877a9cbc-3dd6-44c8-8036-38ed301ebf78_apps-calibre_calibre-library` |
| `apps-calibre/calibre-web-config` | `calibre-web-config-longhorn-rwo` | `pvc-07d490ff-380e-48a9-855a-add0aac8bbbc` | `/var/lib/rancher/k3s/storage/pvc-07d490ff-380e-48a9-855a-add0aac8bbbc_apps-calibre_calibre-web-config` |
| `apps-calibre/kavita-config` | `kavita-config-longhorn-rwo` | `pvc-80d2fd5a-069f-4f5a-883d-ec4f7f5bd474` | `/var/lib/rancher/k3s/storage/pvc-80d2fd5a-069f-4f5a-883d-ec4f7f5bd474_apps-calibre_kavita-config` |
| `apps-openbooks/openbooks-books` | `openbooks-books-longhorn-rwo` | `pvc-33d5016d-6121-4385-8de6-0ecb69247124` | `/var/lib/rancher/k3s/storage/pvc-33d5016d-6121-4385-8de6-0ecb69247124_apps-openbooks_openbooks-books` |
| `apps-openbooks/openbooks-logs` | `openbooks-logs-longhorn-rwo` | `pvc-dcd131a5-54b1-4b21-87a9-83f9006082b6` | `/var/lib/rancher/k3s/storage/pvc-dcd131a5-54b1-4b21-87a9-83f9006082b6_apps-openbooks_openbooks-logs` |
| `apps-ubooquity/ubooquity-config` | `ubooquity-config-longhorn-rwo` | `pvc-b00c4ae1-a24a-4f1f-8bdc-7398739543f5` | `/var/lib/rancher/k3s/storage/pvc-b00c4ae1-a24a-4f1f-8bdc-7398739543f5_apps-ubooquity_ubooquity-config` |
| `apps-uptime-kuma/uptime-kuma-config` | `uptime-kuma-config-longhorn-rwo` | `pvc-b8cee607-4959-4a6f-85de-1b41cd4da13f` | `/var/lib/rancher/k3s/storage/pvc-b8cee607-4959-4a6f-85de-1b41cd4da13f_apps-uptime-kuma_uptime-kuma-config` |

### Procedure

1. Confirm the shell is on the expected machine and get a fresh inventory:

   ```sh
   hostname -s
   kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get pvc -A -o wide
   kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get pv -o wide
   ```

   Continue only if `hostname -s` is `proxmox2-old`, each listed source PVC
   is still Bound to the PV shown above, and each target PVC is Bound. Check
   the Longhorn UI or volume CRs for healthy, two-replica target volumes. Also
   confirm none of the source claims is referenced by a Running or Pending pod
   or by an active Deployment, StatefulSet, DaemonSet, or CronJob template.
   Stop if any names, bindings, workload references, or target health differ.

2. Define the exact source directory list and inspect it before deleting
   anything. This confirms each path exists as a regular directory, is not a
   symlink, and is not itself a mount point; it also records apparent usage.

   ```sh
   paths=(
     /var/lib/rancher/k3s/storage/pvc-73a215bd-653b-44bf-8eb6-60256c5bc919_apps-audiobookshelf_audiobookshelf-config
     /var/lib/rancher/k3s/storage/pvc-79543895-5f34-4245-b3d4-1e9c716b80a1_apps-audiobookshelf_audiobookshelf-metadata
     /var/lib/rancher/k3s/storage/pvc-7b0f9244-8283-4122-8579-ba55bf3cc754_apps-authelia_authelia-config
     /var/lib/rancher/k3s/storage/pvc-dfa615ad-2056-4ba5-854f-a5fe6ea6d28e_apps-calibre_calibre-config
     /var/lib/rancher/k3s/storage/pvc-877a9cbc-3dd6-44c8-8036-38ed301ebf78_apps-calibre_calibre-library
     /var/lib/rancher/k3s/storage/pvc-07d490ff-380e-48a9-855a-add0aac8bbbc_apps-calibre_calibre-web-config
     /var/lib/rancher/k3s/storage/pvc-80d2fd5a-069f-4f5a-883d-ec4f7f5bd474_apps-calibre_kavita-config
     /var/lib/rancher/k3s/storage/pvc-33d5016d-6121-4385-8de6-0ecb69247124_apps-openbooks_openbooks-books
     /var/lib/rancher/k3s/storage/pvc-dcd131a5-54b1-4b21-87a9-83f9006082b6_apps-openbooks_openbooks-logs
     /var/lib/rancher/k3s/storage/pvc-b00c4ae1-a24a-4f1f-8bdc-7398739543f5_apps-ubooquity_ubooquity-config
     /var/lib/rancher/k3s/storage/pvc-b8cee607-4959-4a6f-85de-1b41cd4da13f_apps-uptime-kuma_uptime-kuma-config
   )
   for p in "${paths[@]}"; do
     test -d "$p" && test ! -L "$p" && ! mountpoint -q -- "$p" || {
       echo "STOP: path missing, symlinked, or mounted: $p" >&2
       exit 1
     }
   done
   du -sk -- "${paths[@]}"
   zpool list rpool
   ```

   Review the output and make sure every listed directory is exactly the
   expected source path before proceeding.

3. Delete only the 11 source PVCs. The target Longhorn PVCs are not included:

   ```sh
   kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n apps-audiobookshelf delete pvc audiobookshelf-config audiobookshelf-metadata
   kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n apps-authelia delete pvc authelia-config
   kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n apps-calibre delete pvc calibre-config calibre-library calibre-web-config kavita-config
   kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n apps-openbooks delete pvc openbooks-books openbooks-logs
   kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n apps-ubooquity delete pvc ubooquity-config
   kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n apps-uptime-kuma delete pvc uptime-kuma-config
   ```

   Wait for deletion, then confirm the 11 source PVs are `Released` and still
   use reclaim policy `Retain`. If PVC protection holds a claim, inspect its
   pods. Only remove a **Succeeded** migration-helper pod after confirming its
   copy result is recorded; never force-delete a Running or Pending pod.

4. Recheck the paths and PVs. If they still match this inventory and are not
   mounted, remove only these directories:

   ```sh
   rm -rf -- "${paths[@]}"
   for p in "${paths[@]}"; do test ! -e "$p" || exit 1; done
   ```

5. Delete only the 11 now-Released Retain PV objects, after verifying each PV
   name and phase against the table above:

   ```sh
   kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml delete pv \
     pvc-73a215bd-653b-44bf-8eb6-60256c5bc919 \
     pvc-79543895-5f34-4245-b3d4-1e9c716b80a1 \
     pvc-7b0f9244-8283-4122-8579-ba55bf3cc754 \
     pvc-dfa615ad-2056-4ba5-854f-a5fe6ea6d28e \
     pvc-877a9cbc-3dd6-44c8-8036-38ed301ebf78 \
     pvc-07d490ff-380e-48a9-855a-add0aac8bbbc \
     pvc-80d2fd5a-069f-4f5a-883d-ec4f7f5bd474 \
     pvc-33d5016d-6121-4385-8de6-0ecb69247124 \
     pvc-dcd131a5-54b1-4b21-87a9-83f9006082b6 \
     pvc-b00c4ae1-a24a-4f1f-8bdc-7398739543f5 \
     pvc-b8cee607-4959-4a6f-85de-1b41cd4da13f
   ```

   Finish by confirming all 11 target Longhorn PVCs remain Bound and their
   volumes healthy with two replicas. Record `zpool list rpool` after cleanup
   and the reclaimed `du` total. Leave Mailpile's two local-path PVCs and their
   directories untouched.
