## Refactor Status: `helm-upgrade-apps.sh` ncurses TUI (`dialog`)

### Summary
The refactor has been implemented in [`rancher/helm-upgrade-apps.sh`](/Users/sup/code/bash_configs/rancher/helm-upgrade-apps.sh) with:
- `dialog`-based ncurses interaction.
- Scrolling log window and per-app decision modal.
- Interactive failure handling (`Continue` / `Abort`).
- `--yes`, `--dry-run`, `--help` flags.
- Timestamped logs in `rancher/logs/`.
- End-of-run summary modal with counters.
- Lowercase variable naming across the script.
- Colorized terminal output (enabled by default).

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
     - rollout readiness (`deployment,statefulset` + `kubectl rollout status`),
     - ingress checks for all discovered hosts.
  6. Prompt per-app upgrade decision (unless `--yes`).
  7. Run `helm upgrade` (unless `--dry-run`).
  8. Run postchecks (rollout + ingress HTTP).
- **Failure policy**
  - Failures no longer hard-stop by default.
  - Any failure triggers modal: continue with next app or abort run.
  - Exit status is tracked and returned at end (`1` if any failure happened).

### Interface and Contract
- **CLI flags**
  - `--yes`: auto-approve upgrade/failure prompts.
  - `--dry-run`: skip `helm upgrade`, keep checks and prompts.
  - `--help`: usage text.
- **Exit codes**
  - `0`: completed successfully.
  - `1`: aborted by user or one/more runtime failures.
  - `2`: setup/dependency error (missing command/helper/invalid arg).
- **Helpers kept unchanged**
  - `rancher/zabbix/is-helm-image-up-to-date.sh`
  - `rancher/zabbix/lib/helm-current-version-of-chart.sh`
  - `helm-chart-repo-dir-or-helm-repo.sh` (`/etc/...` primary, local fallback)

### Logging, Counters, and Summary
- **Log file**
  - `rancher/logs/helm-upgrade-YYYYmmdd-HHMMSS.log` per run.
  - File is plain text and append-only for the session.
- **Counters added**
  - `total_discovered_count`, `excluded_count`, `up_to_date_count`, `skipped_count`, `updated_count`, `dry_run_approved_count`, `failed_apps_count`, `failure_events_count`.
- **Final summary modal fields**
  - discovered, excluded, up-to-date, skipped, updated,
  - dry-run approved (when applicable),
  - failed apps, failure events, exit status, log file path.

### Color Output (Implemented)
- Colors are enabled by default (`use_color=1`).
- Colors are disabled only when:
  - `NO_COLOR` is set, or
  - `TERM=dumb`.
- Color rules:
  - Helm app name: blue (`color_blue`).
  - HTTP code: green for `200`, red otherwise (`color_http_code`).
  - Bash return code: green for `0`, red otherwise (`color_bash_rc`).
- Color is applied to terminal output; log file remains uncolored plain text.

### Naming and Style Updates
- Script variables are now lowercase (globals and shared state), including:
  - config paths, mode flags, counters, helper paths, and ingress summary state.

### Validation Performed
- Syntax check: `bash -n rancher/helm-upgrade-apps.sh` (passing).
