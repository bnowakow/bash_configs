## Refactor Status: `helm-upgrade-apps.sh` ncurses TUI (`dialog`)

### Summary
The refactor is fully implemented in [`rancher/helm-upgrade-apps.sh`](/Users/sup/code/bash_configs/rancher/helm-upgrade-apps.sh) with:
- `dialog`-based ncurses interaction.
- Per-app decision modal and summary modal (final log dialog removed).
- Interactive failure handling (`Continue` / `Abort`).
- `--yes`, `--dry-run`, `--rollout-timeout`, `--help` flags.
- Timestamped logs in `rancher/logs/`.
- End-of-run summary modal with counters.
- Lowercase variable naming throughout.
- Colorized terminal output with improved contrast.
- Helper status labels (no magic-number-only output) and consistent status/return_code coloring.
- Added usage documentation in [`rancher/README.md`](/Users/sup/code/bash_configs/rancher/README.md).
- Added Debian logrotate support with installer script.

### Implemented Behavior
- **TUI layer**
  - `show_log_window`: optional scrollable log view (`dialog --tailbox`, used on no-app run path).
  - `show_app_modal`: app metadata + HTTP summary + yes/no approval (`dialog --tailboxbg` + `--yesno`).
  - `ask_on_failure`: failure modal with continue/abort.
  - `show_summary_modal`: final totals modal shown before exit.
- **Workflow phases per app**
  1. Discover app candidates from `helm ls --all-namespaces`.
  2. Exclude system apps via `exclude_patterns` array.
  3. Check update availability via `zabbix/is-helm-image-up-to-date.sh`.
  4. Resolve namespace, local version, target version, chart ref.
  5. Run prechecks:
     - rollout readiness for release-labeled resources only,
     - ingress checks for all discovered hosts.
  6. Prompt per-app upgrade decision (unless `--yes`).
  7. Run `helm upgrade` (unless `--dry-run`).
  8. Run postchecks (rollout + ingress HTTP).
- **Failure policy**
  - Failures do not hard-stop by default.
  - Failures trigger modal: continue with next app or abort run.
  - `exit_status=1` if any failure occurred.

### Interface and Contract
- **CLI flags**
  - `--yes`: auto-approve upgrade/failure prompts.
  - `--dry-run`: skip `helm upgrade`, keep checks and prompts.
  - `--rollout-timeout DURATION`: timeout for each rollout status check (default `90s`).
  - `--help`: usage text.
- **Environment override**
  - `ROLLOUT_TIMEOUT` can set default rollout timeout (used when `--rollout-timeout` is not provided).
- **Exit codes**
  - `0`: completed successfully.
  - `1`: aborted by user or one/more runtime failures.
  - `2`: setup/dependency error (missing command/helper/invalid arg).
- **Helpers kept unchanged**
  - `rancher/zabbix/is-helm-image-up-to-date.sh`
  - `rancher/zabbix/lib/helm-current-version-of-chart.sh`
  - `helm-chart-repo-dir-or-helm-repo.sh` (`/etc/...` primary, local fallback)

### Rollout Check Refinements
- Rollout readiness now targets only resources from the current release via label selector:
  - `app.kubernetes.io/instance=$app`
- This avoids waiting on unrelated deployments in the same namespace.
- Timeout is configurable per rollout call:
  - default `90s`,
  - override with `--rollout-timeout` or `ROLLOUT_TIMEOUT`.

### Logging, Counters, and Summary
- **Log file**
  - `rancher/logs/helm-upgrade-YYYYmmdd-HHMMSS.log` per run.
  - File is plain text and append-only for the run.
- **Counters added**
  - `total_discovered_count`, `excluded_count`, `up_to_date_count`, `skipped_count`, `updated_count`, `dry_run_approved_count`, `failed_apps_count`, `failure_events_count`.
- **Final summary modal fields**
  - discovered, excluded, up-to-date, skipped, updated,
  - dry-run approved (when applicable),
  - failed apps, failure events, exit status, log file path.

### Output and Color Behavior
- Colors are enabled by default (`use_color=1`).
- Colors are disabled only when:
  - `NO_COLOR` is set, or
  - `TERM=dumb`.
- Color mappings:
  - Helm app name: brighter blue (`\033[1;94m`) for better contrast on dark terminals.
  - HTTP code: green for `200`, red otherwise (`color_http_code`).
  - Bash return_code: green for `0`, red otherwise (`color_bash_return_code`).
  - Helper status label:
    - `up_to_date` -> green,
    - `update_available` and `local_newer_than_repo` -> yellow,
    - `unknown` -> red (`color_helper_status`).
  - Helper status return_code:
    - `0` -> green,
    - `1` and `2` -> yellow,
    - other -> red (`color_helper_code`).
- Color is applied to terminal output; log file remains uncolored plain text.
- Dialog color mapping (when supported and colors enabled):
  - App name is blue/bold via `--colors` in the per-app modal body.
  - HTTP codes in ingress summary are bold green for `200`, red otherwise.
  - Dialog colors are only enabled when `dialog --help` reports `--colors`; otherwise `\Z` codes are not emitted.
  - `--colors` is applied to both the tailbox and the yes/no widget to ensure the body renders color sequences.

### Helper Status Labels (Magic Number Removal)
- Added `helper_status_label()` for update-check helper result mapping:
  - `0` -> `up_to_date`
  - `1` -> `update_available`
  - `2` -> `local_newer_than_repo`
  - other -> `unknown`
- User-facing logs include meaningful helper status labels, with numeric return_code as secondary detail.

### Git and Retention Additions
- Added `@logs/` entry to [`.gitignore`](/Users/sup/code/bash_configs/.gitignore).
- Added Debian logrotate files:
  - template: [`rancher/logrotate-helm-upgrade-apps.conf`](/Users/sup/code/bash_configs/rancher/logrotate-helm-upgrade-apps.conf)
  - installer: [`rancher/install-logrotate-helm-upgrade-apps.sh`](/Users/sup/code/bash_configs/rancher/install-logrotate-helm-upgrade-apps.sh)
- Installer behavior:
  - is self-contained (does not require template file at runtime),
  - uses repo-relative resolution (`script_dir`) to build the log glob,
  - installs to `/etc/logrotate.d/helm-upgrade-apps`,
  - supports `--print` and `--help`.

### Naming and Style Updates
- Script variables are lowercase (globals/shared state/config/counters/helpers).
- `rc` terminology replaced with `return_code` in user-facing output and helper variable names.

### Documentation Added
- [`rancher/README.md`](/Users/sup/code/bash_configs/rancher/README.md) includes:
  - requirements,
  - command examples,
  - timeout override usage,
  - runtime flow,
  - log/exit code behavior,
  - color mapping reference.

### Validation Performed
- Syntax check: `bash -n rancher/helm-upgrade-apps.sh` (passing).
- Syntax check: `bash -n rancher/install-logrotate-helm-upgrade-apps.sh` (passing).
