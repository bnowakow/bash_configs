# Repository rename: bash_configs → homelab

Status as of 2026-11-05. GitHub `bnowakow/bash_configs` was renamed to
`bnowakow/homelab`. GitHub redirects the old URL, but nothing should rely on
that.

## Done

| Step | How | Result |
|---|---|---|
| Move checkouts | `./repo-rename.sh` (`repo-rename_playbook.yml`) on proxmox-vms, ovh, nas-local | `~/code/homelab` and `/etc/zabbix/zabbix_agent2.d/homelab` on every host. The old names are temporary symlinks, plus `~/code/bash_configs-clean` on the NAS. Origin points at homelab |
| Rewrite host config | same playbook | Crontabs, `/etc/cron.d`, systemd units, logrotate, sudoers, Zabbix UserParameter confs, sup's dotfiles (`.screenrc`, …) and generated untracked files (e.g. `traefik.yml`). On the NAS also sup's crontab, TrueNAS cron jobs 2 and 3, and init script 2 |
| Rewrite references in the repo | `utilities/rename-repo-references.sh` | 81 files (commit 02679f3) |
| Fix the submodule and locale | `.gitmodules` entry for `ovh/dool/dool`; `.zshrc` falls back to `C.UTF-8` | commit b4dd86b. The missing submodule entry broke Ansible's git module, and the NAS has no `en_US.UTF-8`, which made ansible refuse to start |
| Pull checkouts | git-config / zabbix playbooks | sup and Zabbix checkouts updated; Zabbix confs reinstalled and `zabbix-agent2` restarted |
| Restart services that ran through the symlink | `repo-rename-restart_playbook.yml` (temporary) | Restarted at 20:16 on 2026-11-05 and now active. No process on any host uses `/bash_configs/` |

Services restarted:

| Host | Services |
|---|---|
| proxmox4 | `traefik` |
| proxmox5 | `traefik`, `proxmox-nic-monitor` |
| proxmox-backup-server | `traefik` |
| transmission | `traefik`, `nordvpn-and-transmission` |

## Remaining

1. **Fleet GitRepo URL (proxmox3).** Follow
   `rancher/fleet-repo-rename-handoff.md`, which patches `spec.repo` of
   `fleet-local/rancher-cluster`. Do **not** re-run `rancher/ansible/site.yml`
   for this: its `bootstrap` play reinstalls Rancher/Fleet. Step 4 in the header
   of `repo-rename_playbook.yml` still suggests site.yml, so ignore that line.
2. **Remove the temporary symlinks** once Fleet is confirmed. This refuses to
   run while any checkout still references the old name:
   ```bash
   cd ~/code/homelab/nas/ansible && ./repo-rename.sh -e repo_rename_cleanup=true
   ```
   Afterwards `pgrep -af bash_configs` should print nothing on any host.
3. **TrueNAS init script 1.** It points at
   `nas/change-iptables-bridge-docker-settings.sh`, which was deleted in 2023
   (a20d81e). The migration skipped it, so delete it in System → Advanced →
   Init/Shutdown Scripts.
4. **Delete the temporary migration files** after the cleanup:
   `repo-rename.sh`, `repo-rename_playbook.yml`, `repo-rename_checkout_tasks.yml`,
   `repo-rename-restart.sh`, `repo-rename-restart_playbook.yml`,
   `utilities/rename-repo-references.sh`, this file and
   `rancher/fleet-repo-rename-handoff.md`.

## Not related to the rename

- `traefik` on proxmox2-old is inactive. It was already stopped before the
  restarts. Start it with `sudo systemctl start traefik` if it should run there.

## Gotchas hit during the migration

- **ansible-core 2.14 on the NAS** can't use `get_url`/`uri` against hosts with
  Python ≥ 3.12 (`cert_file` error), so the playbooks use `curl` instead.
- **Locale.** The NAS only has `C.utf8`, so run ansible with `LC_ALL=C.utf8`.
  The wrappers export it.
- **Moving the checkout on the NAS** deleted ansible's working directory. The
  wrappers now `cd /` and use absolute paths.
- **Root-owned generated files** such as transmission's `traefik/traefik.yml`
  need `become` to rewrite, and they block a plain `git pull` as sup.
- **Become passwords differ.** `tmp-zabbix-become-password` works for the
  Proxmox VMs but not for OVH or the NAS.
