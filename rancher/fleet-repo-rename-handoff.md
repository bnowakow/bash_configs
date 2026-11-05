# Handoff: point Fleet at the renamed repository (run on proxmox3)

Written 2026-11-05 on the NAS. Workspace: `/home/sup/code/homelab/rancher` on
**proxmox3**.

## Context

The GitHub repository `bnowakow/bash_configs` was renamed to
`bnowakow/homelab` on 2026-11-05. All host checkouts have already been moved:
`~/code/bash_configs` and `/etc/zabbix/zabbix_agent2.d/bash_configs` are now
temporary symlinks to `…/homelab`, which stay until the cleanup step below.

`rancher/ansible/group_vars/all.yml` already says
`fleet_git_repo_url: https://github.com/bnowakow/homelab.git`, but the live
GitRepo object was created with the old URL. GitHub redirects the old URL, so
Fleet should still be syncing. The goal is to make the live object use the new
URL and confirm Fleet is healthy afterwards.

Object (from the `bootstrap` play of `rancher/ansible/site.yml`):

- kind `GitRepo` (`fleet.cattle.io/v1alpha1`), name `rancher-cluster`,
  namespace `fleet-local`
- branch `master`, path `rancher/fleet`, `clientSecretName: gitcredential`
  (basic-auth secret)

## Do not re-run site.yml for this

`site.yml`'s `bootstrap` play reinstalls Rancher/Fleet, and the `k3s` play
restarts k3s (see `rancher/ansible/README.md`, "Re-apply host configuration
to the running cluster"). A one-field patch of the GitRepo is all that is needed.

## Known issue seen from the NAS

`kubectl get gitrepo -A` on proxmox3 (over a non-interactive ssh) failed with:

```
couldn't get current server API group list: the server could not find the requested resource
Error from server (NotFound): the server could not find the requested resource
```

Before anything else, work out why. Likely causes: the default kubeconfig/context
points at the Rancher proxy instead of the local k3s API, or `KUBECONFIG` is set
differently in a non-login shell. Try:

```bash
kubectl config current-context; kubectl config view --minify | grep server
sudo k3s kubectl get nodes
KUBECONFIG=/etc/rancher/k3s/k3s.yaml sudo -E kubectl get nodes
```

Use whichever works for the rest of this document. Report the cause, but do not
change kubeconfig files without asking.

## Steps

1. Inspect the current state:

   ```bash
   kubectl -n fleet-local get gitrepo rancher-cluster \
     -o jsonpath='{.spec.repo}{"\n"}{.status.commit}{"\n"}{.status.display.readyBundleDeployments}{"\n"}'
   kubectl -n fleet-local get gitrepo rancher-cluster -o yaml | sed -n '/^status:/,$p' | head -60
   ```

   Record the repo URL, the synced commit and the ready count. Compare the
   commit with `git ls-remote https://github.com/bnowakow/homelab.git master`.

2. If `.spec.repo` is still `https://github.com/bnowakow/bash_configs.git`,
   patch only that field:

   ```bash
   kubectl -n fleet-local patch gitrepo rancher-cluster --type merge \
     -p '{"spec":{"repo":"https://github.com/bnowakow/homelab.git"}}'
   ```

   Changing the URL makes Fleet re-clone. Bundles keep their names (they are
   derived from the GitRepo name and paths, not the URL), so no redeploy is
   expected. Do not change `branch`, `paths` or `clientSecretName`.

3. Verify for a few minutes:

   ```bash
   kubectl -n fleet-local get gitrepo rancher-cluster -w
   kubectl get bundles -n fleet-local
   kubectl get bundledeployments -A | grep -v 'Ready' || true
   kubectl -n cattle-fleet-system logs deploy/gitjob --since=10m | tail -50
   ```

   Healthy means: `.status.commit` equals the current `master` SHA of
   `bnowakow/homelab`, the ready count equals the desired count, there are no
   new `ErrApplied`/`NotReady` bundles, and the gitjob logs show no auth or
   clone errors. If the `gitcredential` token was scoped to the old repo name,
   a 403/404 shows up here. Report it; do not rotate the secret yourself.

4. Optional cross-check with the repo's own verification (read-only):

   ```bash
   cd ~/code/homelab/rancher/ansible && ./run.sh --playbook verify.yml --no-ask-become-pass
   ```

## Report back

- kubectl access: what failed and why, and which command worked
- GitRepo URL before and after, synced commit, ready/desired bundle counts
- anything not Ready, with the bundle name and message

## After Fleet is confirmed (done on the NAS, not here)

The NAS runs `nas/ansible/repo-rename.sh -e repo_rename_cleanup=true`, which
removes the `bash_configs` symlinks on every host. Before that, restart the
units that still run from the old path through the symlink:

- proxmox3/4/5, proxmox2-old, proxmox-backup-server, transmission: `traefik`
- proxmox3: nothing else; `/etc/cron.d/emby-upgrade` and logrotate are already rewritten
- proxmox5: `proxmox-nic-monitor`
- transmission: `nordvpn-and-transmission`
- OVH: `docker-resource-monitor`

On proxmox3 only `traefik` applies. Restart it only if the user agrees, and check
`systemctl status traefik` afterwards.

## Verification result — 2026-11-05 19:59 CET

Read `fleet-repo-rename-verification.txt`, collected by the user on proxmox3.
The live GitRepo now uses `https://github.com/bnowakow/homelab.git`; branch,
paths and clientSecretName retain their documented values. Both Fleet's
`status.commit` and GitHub's `refs/heads/master` are
`94e6eae620c97f3741596878bdcad73269c4d390`. Git job status is `Current`,
observed generation is 11 (matching metadata generation). Repository rename
and synchronization are confirmed.

Overall Fleet readiness is **64/69**, so full cluster health is not confirmed:

- `longhorn-backups`: existing `nas-daily-backup` RecurringJob lacks Helm
  ownership metadata required by the bundle.
- `traefik-resources`: existing `pve-proxy/pve-api` Service belongs to release
  namespace `fleet-local`, while the attempted install expects `default`.
- `calibre-storage`: tracked PVCs `calibre-library` and `calibre-web-config`
  in `apps-calibre` are missing.
- `cloudcasa`: deployment drift on `cloudcasa-kubeagent-manager`.
- `cert-manager-resources`: solver configuration drift on `letsencrypt`.

`zabbix` reports bundle readiness 1/1 and BundleDeployment deployed/monitored
True. This report does not inspect running Zabbix container image tags.
The captured gitjob log section has no output; clone-log validation is
inconclusive. There is no before-patch baseline establishing whether all five
bundle issues predate the URL change. No ownership, storage, credentials,
kubeconfig or service restarts were changed during report review. Cleanup of
old symlinks and any Traefik restart remain pending.

Access diagnosis: default kubectl in the agent session has no context; the
explicit k3s kubeconfig selects `https://127.0.0.1:6443`, but agent network
sandboxing denies that socket. User-run commands with the explicit kubeconfig
succeeded. The original NAS NotFound error's cause remains unconfirmed.
