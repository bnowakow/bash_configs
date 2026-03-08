## Refactor Plan: `helm-upgrade-apps.sh` to ncurses TUI (`dialog`)

### Summary
Refactor the current interactive upgrade script into a `dialog`-based ncurses workflow with:
- A persistent scrolling log window for all runtime messages.
- A per-app modal showing `http_code`, current/target chart version, and upgrade decision.
- Interactive failure handling (ask whether to continue).
- Optional non-interactive flags: `--yes` and `--dry-run`.
- Timestamped run logs for audit/debugging.

### Key Implementation Changes
- **TUI architecture**
  - Build a small UI layer in Bash for `dialog` primitives:
    - `show_log_window` (scrollable tail of log file).
    - `show_app_modal` (app summary + yes/no action).
    - `ask_on_failure` (continue/abort modal).
  - Keep one append-only log file per run (e.g. `rancher/logs/helm-upgrade-YYYYmmdd-HHMMSS.log`) and mirror important events there.
- **Workflow restructuring**
  - Split script into explicit phases per app:
    1. Discover candidate app from dynamic list (`helm ls` + excludes).
    2. Check update availability using existing `zabbix/is-helm-image-up-to-date.sh`.
    3. Collect metadata: namespace, repo/chart ref, ingress hosts, current/target versions.
    4. Run prechecks:
       - ingress HTTP checks for **all discovered hosts**.
       - workload readiness checks (rollout/ready gate).
    5. Show modal and decide upgrade (`--yes` bypasses prompt).
    6. Execute `helm upgrade` (or preview only for `--dry-run`).
    7. Run postchecks: rollout readiness + all ingress HTTP checks.
- **Error/decision behavior**
  - Replace hard `exit` on failures with modal choice: `Continue` or `Abort run`.
  - Preserve safe defaults (`No` on upgrade prompt unless `--yes`).
- **Configuration cleanup**
  - Keep dynamic app discovery, but move exclude patterns into a dedicated config array at top of script for easier maintenance.
  - Keep existing Zabbix helper scripts as integration points; only harden parsing/exit handling in caller.
- **CLI/interface additions**
  - New flags:
    - `--yes`: auto-approve upgrades and continue prompts.
    - `--dry-run`: no upgrades; still run discovery/precheck and show decisions.
    - `--help`: usage.

### Public Interfaces / Type Changes
- Script interface changes for [`rancher/helm-upgrade-apps.sh`](/Users/sup/code/bash_configs/rancher/helm-upgrade-apps.sh):
  - Add supported args: `--yes`, `--dry-run`, `--help`.
  - Exit codes:
    - `0` success/completed (possibly with skipped apps),
    - `1` aborted by user or hard failure,
    - `2` dependency/setup issue (e.g., missing `dialog`).
- No planned changes to helper script signatures in [`rancher/zabbix/is-helm-image-up-to-date.sh`](/Users/sup/code/bash_configs/rancher/zabbix/is-helm-image-up-to-date.sh).

### Test Plan
- **Dependency/setup**
  - Missing `dialog` path shows clear error and exit `2`.
- **Candidate/app logic**
  - Apps up-to-date are logged and skipped.
  - Apps with updates show modal with correct version fields.
- **Pre/post checks**
  - Multi-ingress app: all hosts checked; one non-200 triggers failure modal.
  - Rollout check failure triggers failure modal.
- **Modes**
  - Default interactive: per-app modal and failure modal.
  - `--yes`: no decision modals, proceeds automatically.
  - `--dry-run`: no `helm upgrade` executed, but all checks/logging/modals work.
- **Logging**
  - Timestamped log file created and includes phase, app, decision, and check outcomes.

### Assumptions and Defaults
- `dialog` will be installed and available in PATH (required backend).
- Keep current helper scripts and k3s/rancher command paths unchanged.
- Continue using dynamic app discovery with maintained exclude list.
- Rollout readiness checks will be namespace-wide workload checks (deployments/statefulsets) and treated as pass/fail gates.
