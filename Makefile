.PHONY: help install-git-hooks codex-commit cron-install-rancher

.DEFAULT_GOAL := help

help:
	@echo "Rancher helper targets"
	@echo ""
	@echo "  install-git-hooks  Configure repository git hooks"
	@echo "  codex-commit          Commit staged changes with Codex, and optionally push"
	@echo "  cron-install-rancher  Install Rancher maintenance cron and logrotate"

install-git-hooks:
	git config core.hooksPath .githooks
	chmod +x .githooks/pre-commit
	@if bash .githooks/pre-commit --check-dependencies; then \
		ggshield auth login --method oob; \
	else \
		printf 'Install ggshield now? [y/N] '; \
		read -r answer; \
		case "$$answer" in \
			y|Y|yes|YES) \
				if ! command -v pipx >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then \
					sudo apt-get install -y pipx; \
				fi; \
				if command -v pipx >/dev/null 2>&1; then \
					pipx install ggshield; \
				elif command -v sudo >/dev/null 2>&1; then \
					sudo python3 -m pip install --break-system-packages ggshield; \
				else \
					printf 'Unable to install ggshield: pipx and sudo are unavailable.\n' >&2; \
					exit 1; \
				fi; \
				bash .githooks/pre-commit --check-dependencies; \
				ggshield auth login --method oob; \
				;; \
			*) printf 'ggshield was not installed; secrets will not be verified for commits.\n' ;; \
			esac; \
	fi
	@echo "✓ Git hooks installed"

codex-commit:
	utilities/codex-commit.sh

cron-install-rancher:
	rancher/install-cron-rancher.sh
