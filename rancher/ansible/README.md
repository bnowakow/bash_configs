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

## Prepare

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
cp inventory/hosts.ini.example inventory/hosts.ini
cp group_vars/all.yml.example group_vars/all.yml
cp .env.sample .env
```

Edit the inventory and variables. In particular, verify `longhorn_device`; formatting
is disabled by default and the playbook fails if the device has no filesystem UUID.
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
```

`./run.sh` loads `ansible/.env` automatically. Use `--env-file FILE` or the
`ANSIBLE_ENV_FILE` environment variable to select another file. Variables already
exported in the shell are overwritten by values from the selected `.env` file.

The playbook does not delete data, format a disk unless `longhorn_format_device: true`
is explicitly set, or restore CloudCasa backups. Restore PVC data only after Fleet has
installed Longhorn and its storage class is healthy.
