VENV := /tmp/llm-cheatsheet-venv
PYTHON := $(VENV)/bin/python
PIP := $(VENV)/bin/pip

.PHONY: llm-cheatsheet

llm-cheatsheet:
	python3 -m venv "$(VENV)"
	"$(PIP)" install reportlab
	"$(PYTHON)" llm_model_cheatsheet.py
