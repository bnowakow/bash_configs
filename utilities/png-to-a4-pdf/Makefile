.PHONY: help venv install-requirements png-to-a4-pdf

.DEFAULT_GOAL := help

PYTHON ?= python3
VENV := .venv
VENV_PYTHON := $(VENV)/bin/python
PNG_TO_A4_PDF_ARGS ?=

help:
	@echo "Utility targets"
	@echo ""
	@echo "  venv                  Create a local Python virtual environment"
	@echo "  install-requirements  Install Python dependencies for utilities"
	@echo "  png-to-a4-pdf         Convert INPUT PNG to OUTPUT PDF using the local venv"

$(VENV_PYTHON):
	$(PYTHON) -m venv $(VENV)

venv: $(VENV_PYTHON)

install-requirements: $(VENV_PYTHON)
	$(VENV_PYTHON) -m pip install -r requirements.txt

png-to-a4-pdf: install-requirements
	@if [ -z "$(INPUT)" ] || [ -z "$(OUTPUT)" ]; then \
		echo "Usage: make png-to-a4-pdf INPUT=input.png OUTPUT=output.pdf"; \
		echo "Optional: PNG_TO_A4_PDF_ARGS='--margin-mm 10 --overlap-mm 5'"; \
		exit 2; \
	fi
	$(VENV_PYTHON) png-to-a4-pdf.py "$(INPUT)" "$(OUTPUT)" $(PNG_TO_A4_PDF_ARGS)
