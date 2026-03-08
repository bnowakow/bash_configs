# Helm Upgrade Codex Refactor

This repository branch (`helm-upgrade-codex-refactor`) includes a refactored ncurses-based Helm upgrade flow for k3s/Rancher in:
- `rancher/helm-upgrade-apps.sh`

## What Changed

The script now provides:
- `dialog` ncurses UI (log window, per-app modal, failure modal)
- safer upgrade flow with precheck/postcheck
- interactive failure handling (`Continue` / `Abort`)
- run summary modal with counters
- colorized terminal output
- readable helper status labels (`up_to_date`, `update_available`, `local_newer_than_repo`, `unknown`)

## Requirements

Install/ensure these commands are available:
- `dialog`
- `helm`
- `kubectl`
- `curl`
- `sudo`

Also required helper scripts:
- `rancher/zabbix/is-helm-image-up-to-date.sh`
- `rancher/zabbix/lib/helm-current-version-of-chart.sh`
- `rancher/zabbix/lib/helm-chart-repo-dir-or-helm-repo.sh`
  - script first tries `/etc/zabbix/zabbix_agent2.d/bash_configs/rancher/zabbix/lib/helm-chart-repo-dir-or-helm-repo.sh`

## Usage

From repo root:

```bash
./rancher/helm-upgrade-apps.sh
```

Options:

```bash
./rancher/helm-upgrade-apps.sh --help
./rancher/helm-upgrade-apps.sh --yes
./rancher/helm-upgrade-apps.sh --dry-run
./rancher/helm-upgrade-apps.sh --rollout-timeout 120s
./rancher/helm-upgrade-apps.sh --yes --rollout-timeout=60s
```

Environment override for rollout timeout:

```bash
ROLLOUT_TIMEOUT=2m ./rancher/helm-upgrade-apps.sh
```

## Runtime Behavior

Per app, the script does:
1. checks update availability via helper script
2. collects namespace/version/chart metadata
3. runs prechecks:
   - rollout checks only for release-labeled resources: `app.kubernetes.io/instance=<app>`
   - ingress HTTP checks for all discovered hosts
4. asks whether to upgrade (unless `--yes`)
5. runs `helm upgrade` (unless `--dry-run`)
6. runs postchecks (rollout + ingress)

## Logs and Exit Codes

Logs are written to:
- `rancher/logs/helm-upgrade-YYYYmmdd-HHMMSS.log`

Exit codes:
- `0` success/completed
- `1` aborted by user or runtime failure
- `2` setup/dependency/argument error

## Color Rules

Default: colors enabled.
Colors are disabled only when:
- `NO_COLOR` is set, or
- `TERM=dumb`

Color mapping:
- app name: bright blue
- HTTP `200`: green; non-`200`: red
- bash return_code `0`: green; non-`0`: red
- helper status:
  - `up_to_date`: green
  - `update_available`, `local_newer_than_repo`: yellow
  - `unknown`: red
