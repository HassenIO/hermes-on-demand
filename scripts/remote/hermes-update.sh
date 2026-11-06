#!/usr/bin/env bash
# Runs ON the VPS. Safe Hermes upgrade that re-applies our local fixes.
#
# Upstream `hermes update` can overwrite docker.py and break Telegram sandboxes
# (colon in session paths). The host path re-runs the patch and refreshes CLI links.
# HERMES_DOCKER_RUNTIME=1 pulls the official image and recreates; it does not
# run hermes update. A host patch failure on that path does not abort recreate.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/hermes-docker.sh
source "$SCRIPT_DIR/../lib/hermes-docker.sh"

export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"

run_hermes_upgrade \
  "$SCRIPT_DIR/patch-hermes-docker.sh" \
  "$(hermes_compose_file)" \
  "$SCRIPT_DIR/hermes-docker-up.sh"
if docker_runtime_requested; then
  if [[ -f "$SCRIPT_DIR/pin-cron-models.sh" ]]; then
    bash "$SCRIPT_DIR/pin-cron-models.sh" || warn "cron model pin failed"
  fi
  log "Update + repair finished"
  exit 0
fi

command -v hermes >/dev/null 2>&1 || die "hermes not on PATH"

# Re-link CLI (root FHS + user local)
if [[ -x /usr/local/lib/hermes-agent/venv/bin/hermes ]]; then
  ln -sfn /usr/local/lib/hermes-agent/venv/bin/hermes /usr/local/bin/hermes
  mkdir -p "${HOME}/.local/bin"
  # Never create a self-referential loop
  if [[ -L "${HOME}/.local/bin/hermes" ]]; then
    target="$(readlink "${HOME}/.local/bin/hermes" || true)"
    if [[ "$target" == "${HOME}/.local/bin/hermes" || "$target" == "hermes" ]]; then
      rm -f "${HOME}/.local/bin/hermes"
    fi
  fi
  ln -sfn /usr/local/lib/hermes-agent/venv/bin/hermes "${HOME}/.local/bin/hermes"
fi

log "Re-applying Docker path sanitize"
bash "$SCRIPT_DIR/patch-hermes-docker.sh"

if [[ -f "$SCRIPT_DIR/install-artifacts.sh" ]]; then
  log "Refreshing artifacts (profile seeds)"
  bash "$SCRIPT_DIR/install-artifacts.sh" || true
fi

# Upgrade Mnemosyne side-venv if present (survives Hermes venv rebuilds)
VENV="${MNEMOSYNE_VENV:-$HERMES_HOME/.mnemosyne/venv}"
if [[ -x "$VENV/bin/python" && -x "$VENV/bin/mnemosyne-hermes" ]]; then
  log "Upgrading Mnemosyne side-venv"
  PROFILE="${MNEMOSYNE_PROFILE:-embeddings}"
  case "$PROFILE" in
    all) REQ="mnemosyne-memory[all]" ;;
    *) REQ="mnemosyne-memory[embeddings]" ;;
  esac
  "$VENV/bin/python" -m pip install --upgrade "$REQ" mnemosyne-hermes || warn "Mnemosyne pip upgrade failed"
  "$VENV/bin/mnemosyne-hermes" install --mode wrapper --python "$VENV/bin/python" --force || warn "wrapper refresh failed"
  "$VENV/bin/mnemosyne-hermes" status || true
fi

# Refresh Agent-Reach image + skill if previously installed
if docker image inspect "${AGENT_REACH_IMAGE:-hermes-terminal:agent-reach}" >/dev/null 2>&1 \
  || [[ -f "$HERMES_HOME/skills/agent-reach/SKILL.md" ]]; then
  if [[ -f "$SCRIPT_DIR/agent-reach-up.sh" ]]; then
    log "Refreshing Agent-Reach (image + skill)"
    bash "$SCRIPT_DIR/agent-reach-up.sh" || warn "Agent-Reach refresh failed"
  fi
fi

# Refresh Notion only if both credentials still present on VPS
if [[ -f "$SCRIPT_DIR/notion-up.sh" && -f "$HERMES_HOME/.env" ]]; then
  _nk="$(grep -E '^NOTION_API_KEY=.' "$HERMES_HOME/.env" 2>/dev/null | head -1 || true)"
  _np="$(grep -E '^NOTION_REPORTS_PARENT_PAGE_ID=.' "$HERMES_HOME/.env" 2>/dev/null | head -1 || true)"
  if [[ -n "$_nk" && -n "$_np" ]]; then
    log "Refreshing Notion (REST CLI + skill)"
    bash "$SCRIPT_DIR/notion-up.sh" || warn "Notion refresh failed"
  else
    log "Skipping Notion refresh (need both NOTION_API_KEY and NOTION_REPORTS_PARENT_PAGE_ID)"
  fi
fi

log "Restarting gateway"
if ! start_host_gateway; then
  if hermes_container_running; then
    die "refusing host gateway start while container hermes is running"
  fi
  warn "host gateway start failed"
fi
sleep 3
hermes gateway status 2>/dev/null || true
hermes memory status 2>&1 || true

# Keep cron jobs pinned to config.yaml model (avoid drift_skip after model changes)
if [[ -f "$SCRIPT_DIR/pin-cron-models.sh" ]]; then
  bash "$SCRIPT_DIR/pin-cron-models.sh" || warn "cron model pin failed"
fi

log "Update + repair finished"
