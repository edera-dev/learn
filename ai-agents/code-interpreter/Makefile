# Code Interpreter agent with Edera-isolated tool calls
#
# Usage:
#   make template       # install the SandboxTemplate
#   make check          # verify sandbox plumbing (no API key needed)
#   make run            # run the agent (needs ANTHROPIC_API_KEY)
#   make clean          # remove template and any sandboxes

VENV ?= .venv
PY = $(VENV)/bin/python
PIP = $(VENV)/bin/pip

.PHONY: help venv template check run clean

help:
	@echo "Code Interpreter agent with Edera-isolated tool calls"
	@echo ""
	@echo "Usage:"
	@echo "  make template   Install the SandboxTemplate and SandboxWarmPool"
	@echo "  make check      Verify sandbox write/run plumbing (no API key needed)"
	@echo "  make run        Run the agent REPL (needs ANTHROPIC_API_KEY)"
	@echo "  make clean      Remove the template, warm pool, and any sandboxes"

venv: $(VENV)/bin/python

$(VENV)/bin/python:
	python3 -m venv $(VENV)
	$(PIP) install -q --upgrade pip
	$(PIP) install -q -r requirements.txt

template:
	kubectl apply -f sandbox-template.yaml
	kubectl apply -f sandbox-warmpool.yaml

check: venv template
	$(PY) check_sandbox.py

run: venv template
	$(PY) agent.py

clean:
	kubectl delete -f sandbox-warmpool.yaml --ignore-not-found
	kubectl delete -f sandbox-template.yaml --ignore-not-found
	-kubectl delete sandboxes.agents.x-k8s.io --all
