# Ansible cluster bootstrap

This is a bootstrap playbook for a Debian-family K3s cluster. It prepares Longhorn
hosts, installs K3s, installs Rancher, enables Rancher's bundled Fleet controllers,
configures kube-vip and Traefik, and registers this repository's `fleet/` path with
Fleet.

Longhorn and cert-manager are installed by Fleet after the `GitRepo` becomes ready;
the playbook intentionally does not install those Helm releases directly. This gives
Fleet ownership from the beginning and avoids a later Helm-controller ownership
handoff.

Set `CLOUDCASA_CLUSTER_ID` to the ID from the CloudCasa portal to create the values
Secret used by the Fleet CloudCasa bundle. Also set `CLOUDFLARE_API_TOKEN`; both
values are read from the environment and are not stored in Git. The CloudCasa agent
chart itself is still a normal HTTP Helm repo;
its current vendor repository does not provide an OCI URL.

During a normal bootstrap, the playbook reads the current Kubernetes `kube-system`
namespace UID, prints it, and pauses for confirmation. Before typing `yes`, update the
registered Kube System UID for this cluster in CloudCasa under **Clusters > Overview**.
Do not delete or recreate the `kube-system` namespace. If CloudCasa does not expose the
field, ask CloudCasa support to update the registered UID instead.

After you confirm the update by typing `yes`, the playbook restarts the
`cloudcasa-kubeagent-manager` Deployment and waits for its rollout to complete.

## Prepare

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
cp inventory/hosts.ini.example inventory/hosts.ini
cp group_vars/all.yml.example group_vars/all.yml
cp .env.sample .env
```

Edit the inventory and variables. In particular, verify that each Longhorn host's
dedicated filesystem has the configured `longhorn_filesystem_label` (default:
`longhorn`); the playbook resolves the device path per host with `blkid`. Formatting
is disabled by default and the playbook fails if the device has no filesystem UUID.
`dm_crypt` is loaded and persisted (`longhorn_dm_crypt_enabled: true`) because the
`longhorn-crypto-2replicas` StorageClass uses LUKS-encrypted Longhorn volumes.
The inventory includes `nas.localdomain.bnowakowski.pl` as a third K3s server so embedded
etcd can regain an odd-numbered quorum. The NAS is intentionally not in
`longhorn_nodes`, so the Longhorn disk preparation tasks are not run there. Set
`NAS_ANSIBLE_USER` and `NAS_ANSIBLE_PASSWORD` in `.env`; the same password is used for
SSH and sudo/become and is not committed. If the password is omitted from `.env`,
`run.sh` asks for it once, silently, when the NAS is selected.
By default, the playbook creates a basic-auth Secret for the private GitHub repository
from `GITHUB_USERNAME` and `GITHUB_TOKEN`. A fine-grained GitHub token with read access
to this repository is sufficient. To use SSH instead, set `fleet_git_auth_type: ssh`
and pre-create the Secret in `fleet-local`; Fleet documents that credential as type
`kubernetes.io/ssh-auth`.

## Run

```bash
./run.sh
```

The wrapper supports common execution modes:

```bash
./run.sh --syntax-check
./run.sh --check --diff
./run.sh --limit proxmox3
./run.sh --limit longhorn_nodes
./run.sh --no-ask-become-pass
./run.sh --playbook verify.yml --no-ask-become-pass
```

Use `./run.sh --help` for all options. Additional `ansible-playbook` options can be
passed after `--`.

After a successful normal bootstrap, `run.sh` automatically invokes the verification
playbook. It waits for all K3s nodes, Longhorn pods and nodes, the Longhorn StorageClass,
CloudCasa pods, and the Fleet GitRepo:

```bash
./run.sh --playbook verify.yml --no-ask-become-pass
```

The explicit command above is useful for rechecking health later. Verification is not
automatically invoked for `--check`, `--syntax-check`, `--list-hosts`, or another selected
playbook.

Edit `.env` with the external values:

```dotenv
RANCHER_BOOTSTRAP_PASSWORD='replace-me'
CLOUDFLARE_API_TOKEN='replace-me'
CLOUDCASA_CLUSTER_ID='replace-me'
GITHUB_USERNAME='replace-me'
GITHUB_TOKEN='replace-me'
NAS_ANSIBLE_USER='sup'
NAS_ANSIBLE_PASSWORD='replace-me'
```

`./run.sh` loads `ansible/.env` automatically. Use `--env-file FILE` or the
`ANSIBLE_ENV_FILE` environment variable to select another file. Variables already
exported in the shell are overwritten by values from the selected `.env` file.

The playbook does not delete data, format a disk unless `longhorn_format_device: true`
is explicitly set, or restore CloudCasa backups. Restore PVC data only after Fleet has
installed Longhorn and its storage class is healthy.

## Re-apply host configuration to the running cluster

`run.sh` is a full bootstrap. On a live cluster it would restart k3s, upgrade
it to `k3s_version` and reinstall Rancher/Fleet. To push host-level changes
(packages, iscsid, sysctl, the Longhorn mount) to the existing nodes, use:

```bash
./run-cluster-nodes.sh --check --diff   # preview; changes nothing
./run-cluster-nodes.sh                  # apply to proxmox3 and proxmox2-old
./run-cluster-nodes.sh --limit proxmox2-old
./run-cluster-nodes.sh --become-password-file ../../tmp-sudo-password
```

It uses `inventory/k3s-cluster.ini`, which lists only the k3s nodes. That file
is generated by `./sync-k3s-inventory.sh`: it takes the hosts of
`nas/ansible/inventory/proxmox-vms.yml` (not all of which are k3s nodes) and
keeps those whose short name (`proxmox3.localdomain…` → `proxmox3`) is a node
in `kubectl get nodes`. Control-plane nodes go to `k3s_servers`, the others to
`k3s_agents`, and nodes with a Longhorn node object to `longhorn_nodes`. k3s
nodes missing from the Proxmox inventory are reported as warnings, not added.
Re-run it after adding or removing a node; `--check` only shows the diff and
exits 1 when the file is out of date. `run-cluster-nodes.sh` warns when it is.

```bash
./sync-k3s-inventory.sh --check   # show the diff only
./sync-k3s-inventory.sh           # rewrite inventory/k3s-cluster.ini
```

 It runs only the `host-prep` and `longhorn-disks`
plays of `site.yml`. The `k3s` and `bootstrap` tags are refused unless
`--allow-cluster-changes` is given. Every play in `site.yml` is tagged:

| Tag | Play |
| --- | --- |
| `host-prep` | packages, iscsid, dm_crypt, `bridge-nf-call-iptables=1` |
| `longhorn-disks` | find and mount the `longhorn`-labelled filesystem |
| `k3s` | install/upgrade/join k3s, **always restarts k3s** |
| `bootstrap` | Helm, Rancher, Fleet, secrets, GitRepo |

The same commands are available from `rancher/` through make (`make` lists them):

```bash
make k3s-inventory-check   # ./sync-k3s-inventory.sh --check
make k3s-inventory         # ./sync-k3s-inventory.sh
make k3s-nodes-check       # ./run-cluster-nodes.sh --check --diff
make k3s-nodes-apply ARGS="--limit proxmox3"
```

Validated on 2026-11-02 with `--check --diff`: both nodes 12 ok, 0 changed,
0 failed.
