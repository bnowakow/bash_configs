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
	@echo "✓ Git hooks installed"

codex-commit:
	utilities/codex-commit.sh

cron-install-rancher:
	rancher/install-cron-rancher.sh
