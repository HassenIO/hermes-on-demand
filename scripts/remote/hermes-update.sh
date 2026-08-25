#!/usr/bin/env bash
# Runs ON the VPS. Safe Hermes upgrade that re-applies our local fixes.
#
# Upstream `hermes update` can overwrite docker.py and break Telegram sandboxes
# (colon in session paths). Always re-run the patch + refresh CLI links.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"

command -v hermes >/dev/null 2>&1 || die "hermes not on PATH"

log "Running hermes update"
hermes update || warn "hermes update exited non-zero — continuing with repair steps"

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

# Refresh Notion MCP + skill if previously configured
if [[ -f "$HERMES_HOME/skills/notion-reports/SKILL.md" ]] \
  || grep -qE '^\s+notion:' "$HERMES_HOME/config.yaml" 2>/dev/null; then
  if [[ -f "$SCRIPT_DIR/notion-up.sh" ]]; then
    log "Refreshing Notion (MCP + skill)"
    bash "$SCRIPT_DIR/notion-up.sh" || warn "Notion refresh failed"
  fi
fi

log "Restarting gateway"
hermes gateway restart 2>/dev/null || hermes gateway start 2>/dev/null || true
sleep 3
hermes gateway status 2>/dev/null || true
hermes memory status 2>&1 || true

log "Update + repair finished"
