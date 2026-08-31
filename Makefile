# Hermes VPS control plane — Mac only. Never installs Hermes on this machine.
# Usage: make <target>   |   make help

.DEFAULT_GOAL := help
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
DEPLOY := $(ROOT)/scripts/deploy.sh

.PHONY: help check-env ssh \
	deploy full push-config push-artifacts health update \
	setup-firecrawl setup-mnemosyne setup-agent-reach setup-notion

# ── Primary ───────────────────────────────────────────────────────────

help: ## Show this help
	@echo "Hermes VPS deploy (Mac control plane)"
	@echo ""
	@echo "Most used:"
	@echo "  make deploy            Full bootstrap / refresh stack"
	@echo "  make push-config       Push .env + config.yaml + artifacts, restart"
	@echo "  make push-artifacts    Push SOUL/USER/MEMORY/CV only"
	@echo "  make health            Remote healthcheck"
	@echo "  make update            hermes update + repairs"
	@echo "  make ssh               Interactive SSH to TARGET_HOST"
	@echo ""
	@echo "Setup extensions:"
	@echo "  make setup-firecrawl     SearXNG + Firecrawl lite"
	@echo "  make setup-mnemosyne     Mnemosyne memory provider"
	@echo "  make setup-agent-reach   Terminal image + internet CLIs skill"
	@echo "  make setup-notion        Notion REST CLI (needs both NOTION_* env vars)"
	@echo ""
	@echo "All targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-22s %s\n", $$1, $$2}'
	@echo ""
	@echo "Docs: README.md  |  docs/  |  docs/tools/"

check-env: ## Verify .env exists (does not print secrets)
	@test -f "$(ROOT)/.env" || { echo "ERROR: missing .env — cp .env.sample .env"; exit 1; }
	@echo "OK  $(ROOT)/.env"

ssh: check-env ## Interactive SSH shell on TARGET_HOST (from .env)
	@set -a && source "$(ROOT)/.env" && set +a && \
	: "$${TARGET_HOST:?TARGET_HOST missing in .env}" && \
	: "$${TARGET_USER:?TARGET_USER missing in .env}" && \
	SSH_PORT="$${SSH_PORT:-22}" && \
	opts=(-o StrictHostKeyChecking=accept-new -p "$$SSH_PORT") && \
	if [[ -n "$${SSH_IDENTITY_FILE:-}" ]]; then opts+=(-i "$$SSH_IDENTITY_FILE"); fi && \
	exec ssh "$${opts[@]}" "$${TARGET_USER}@$${TARGET_HOST}"

deploy: check-env ## Full remote bootstrap / refresh default stack
	@$(DEPLOY)

full: deploy ## Alias for make deploy

push-config: check-env ## Push secrets + config.yaml + artifacts; restart gateway
	@$(DEPLOY) --config-only

push-artifacts: check-env ## Push profile seeds (SOUL / USER / MEMORY / CV)
	@$(DEPLOY) --artifacts

health: check-env ## Remote healthcheck
	@$(DEPLOY) --health

update: check-env ## hermes update + Docker patch + extension refresh
	@$(DEPLOY) --update

# ── Extensions ────────────────────────────────────────────────────────

setup-firecrawl: check-env ## Deploy SearXNG + Firecrawl lite (search + extract)
	@$(DEPLOY) --firecrawl

setup-mnemosyne: check-env ## Install/refresh Mnemosyne side-venv + wrapper
	@$(DEPLOY) --mnemosyne

setup-agent-reach: check-env ## Build agent-reach Docker image + skill
	@$(DEPLOY) --agent-reach

setup-notion: check-env ## Notion REST CLI + skill (no-op unless both NOTION_* vars set)
	@$(DEPLOY) --notion
