## Refactor Status: `helm-upgrade-apps.sh` ncurses TUI (`dialog`)

### Summary
The refactor is fully implemented in [`rancher/helm-upgrade-apps.sh`](/Users/sup/code/bash_configs/rancher/helm-upgrade-apps.sh) with:
- `dialog`-based ncurses interaction.
- Scrolling log window and per-app decision modal.
- Interactive failure handling (`Continue` / `Abort`).
- `--yes`, `--dry-run`, `--rollout-timeout`, `--help` flags.
- Timestamped logs in `rancher/logs/`.
- End-of-run summary modal with counters.
- Lowercase variable naming throughout.
- Colorized terminal output with improved contrast.
- Helper status labels (no magic-number-only output) and consistent status/code coloring.

### Implemented Behavior
- **TUI layer**
  - `show_log_window`: final scrollable log view (`dialog --tailbox`).
  - `show_app_modal`: app metadata + HTTP summary + yes/no approval (`dialog --tailboxbg` + `--yesno`).
  - `ask_on_failure`: failure modal with continue/abort.
  - `show_summary_modal`: final totals modal before log window.
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
  - Bash return code: green for `0`, red otherwise (`color_bash_rc`).
  - Helper status label:
    - `up_to_date` -> green,
    - `update_available` and `local_newer_than_repo` -> yellow,
    - `unknown` -> red (`color_helper_status`).
  - Helper status code:
    - `0` -> green,
    - `1` and `2` -> yellow,
    - other -> red (`color_helper_code`).
- Color is applied to terminal output; log file remains uncolored plain text.

### Helper Status Labels (Magic Number Removal)
- Added `helper_status_label()` for update-check helper result mapping:
  - `0` -> `up_to_date`
  - `1` -> `update_available`
  - `2` -> `local_newer_than_repo`
  - other -> `unknown`
- User-facing logs include meaningful helper status labels, with numeric code as secondary detail.
- Fixed color consistency bug: in `helper status: ..., code: ...`, `code: 0` is green (success).

### Naming and Style Updates
- Script variables are lowercase (globals/shared state/config/counters/helpers).

### Validation Performed
- Syntax check: `bash -n rancher/helm-upgrade-apps.sh` (passing).
