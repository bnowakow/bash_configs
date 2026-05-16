# k3s + Rancher Upgrade Script

## Summary
Create `upgrade-k3s-rancher.sh` as a root-only, confirmation-gated upgrade script for the current k3s server node, cert-manager, and Rancher. It uses live version discovery, shows the SUSE/GitHub source URLs and selected versions, creates a pre-upgrade snapshot when possible, then proceeds only after explicit confirmation.

Current source facts found during planning:
- Latest Rancher matrix: [Rancher Manager v2.14.1](https://www.suse.com/suse-rancher/support-matrix/all-supported-versions/rancher-v2-14-1/)
- Rancher `v2.14.1` certifies k3s up to Kubernetes `v1.35`.
- Latest matching k3s stable release found: `v1.35.4+k3s1`.
- Latest cert-manager stable release found: `v1.20.2`.

## Key Implementation
- Add strict Bash setup:
  - `set -Eeuo pipefail`
  - exit unless `EUID == 0`
  - timestamped log file under `"$script_dir/logs"`
  - dependency checks for `curl`, `helm`, `kubectl`, `systemctl`, `cp`, `chmod`, `hostname`, and parsing tools.
- Reuse from `helm-upgrade-apps.sh`:
  - `kubeconfig_path="/etc/rancher/k3s/k3s.yaml"`
  - `script_dir`, `log_dir`, `log_file`
  - compact `require_cmd` and logging helpers.
- Use `export KUBECONFIG="$kubeconfig_path"` and also pass `--kubeconfig "$kubeconfig_path"` to Helm/kubectl commands where practical.
- Keep the script terminal-based. Do not copy the `dialog` UI from `helm-upgrade-apps.sh`.

## Upgrade Flow
- Discover live versions:
  - Resolve latest Rancher support matrix page from SUSE.
  - Parse Rancher version and supported k3s Kubernetes minor from the matrix.
  - Query GitHub releases for `k3s-io/k3s`, filter to stable tags matching the supported minor, exclude RC/prerelease tags, choose highest patch.
  - Query GitHub releases for `cert-manager/cert-manager`, exclude RC/prerelease tags, choose highest stable tag.
  - If discovery fails, exit before making changes.
- Print and log:
  - Rancher version and clickable support matrix URL.
  - supported k3s minor.
  - selected k3s tag.
  - selected cert-manager tag.
  - current installed k3s, cert-manager, and Rancher versions when detectable.
- Safety checkpoint:
  - show `kubectl get nodes` and relevant pod status for `cert-manager` and `cattle-system` if reachable.
  - run `k3s etcd-snapshot save --name "pre-rancher-upgrade-<timestamp>"` when available.
  - if snapshot is unavailable or fails, ask whether to continue.
  - require typed confirmation before any upgrade command runs.
- Upgrade k3s current node only:
  - URL-encode `+` in the selected k3s tag for `INSTALL_K3S_VERSION`.
  - run `curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="<encoded-tag>" sh -s - server`.
  - copy `"$script_dir/config.yaml"` to `/etc/rancher/k3s/config.yaml`.
  - `chmod 644 /etc/rancher/k3s/config.yaml`.
  - restart with `systemctl stop k3s` then `systemctl start k3s`.
  - wait until `kubectl get nodes` succeeds.
- Helm repos:
  - add `rancher-stable` only if missing.
  - add `jetstack` only if missing.
  - run `helm repo update`.
- cert-manager:
  - use `helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version "$cert_manager_version" --set startupapicheck.timeout=5m --set crds.enabled=true`.
  - apply `https://github.com/jetstack/cert-manager/releases/download/$cert_manager_version/cert-manager.crds.yaml` twice.
  - show `kubectl get pods --namespace cert-manager`.
- Rancher:
  - use `helm upgrade --install rancher rancher-stable/rancher --namespace cattle-system --create-namespace`.
  - preserve settings from `install.sh`:
    - `hostname=$(hostname).tailscale.bnowakowski.pl`
    - `bootstrapPassword=admin`
    - `ingress.tls.source=letsEncrypt`
    - `letsEncrypt.email=dobrowolski.nowakowski@gmail.com`
  - run rollout/status checks.
  - print final setup URL with bootstrap secret.
- Finish with `"$script_dir/rancher_add_cluster_repos.sh"`.

## Improvements Included
- `helm upgrade --install` for Rancher and cert-manager.
- idempotent Helm repo setup.
- live version discovery with fail-closed behavior.
- pre-upgrade snapshot when possible.
- current version/status display before changes.
- all risky commands logged and printed.
- timestamped run log.
- portable `"$script_dir/config.yaml"` instead of hardcoded `/home/sup/...`.
- current-node-only upgrade for v1, no SSH multi-node automation.

## Test Plan
- `bash -n upgrade-k3s-rancher.sh`.
- Run as non-root and verify immediate exit.
- Run discovery path and confirm:
  - Rancher support URL resolves.
  - k3s supported minor parses correctly.
  - selected k3s release is stable and matches the supported minor.
  - selected cert-manager release is stable.
- Run on target host and stop at confirmation prompt to verify displayed URLs/versions.
- Full acceptance:
  - snapshot step either succeeds or requires explicit override.
  - k3s restarts cleanly.
  - `kubectl get nodes` succeeds.
  - cert-manager pods are visible/healthy.
  - Rancher rollout succeeds.
  - dashboard setup URL is printed.
  - `rancher_add_cluster_repos.sh` completes.

## Assumptions
- The script upgrades only the current k3s server node.
- `/etc/rancher/k3s/k3s.yaml` remains the kubeconfig.
- Latest means highest stable/non-RC compatible version.
- Network access to SUSE, GitHub, get.k3s.io, and Helm repos is required.
- If live lookup fails, the script exits instead of falling back to stale pinned versions.
