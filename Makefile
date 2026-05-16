.PHONY: help install-git-hooks

.DEFAULT_GOAL := help

help:
	@echo "Rancher helper targets"
	@echo ""
	@echo "  install-git-hooks  Configure repository git hooks"

install-git-hooks:
	git config core.hooksPath .githooks
	chmod +x .githooks/pre-commit
	@echo "✓ Git hooks installed"
