#!/usr/bin/env bash
# Runs ON the VPS. Exit non-zero if Hermes/gateway/docker look broken.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
failed=0

check() {
  local name="$1"
  shift
  if "$@"; then
    log "OK  $name"
  else
    warn "FAIL $name"
    failed=1
  fi
}

# Prefer real binary if ~/.local/bin has a broken symlink loop
if [[ -L "${HOME}/.local/bin/hermes" ]]; then
  if ! readlink -f "${HOME}/.local/bin/hermes" >/dev/null 2>&1; then
    warn "fixing broken hermes symlink at ~/.local/bin/hermes"
    ln -sfn /usr/local/lib/hermes-agent/venv/bin/hermes "${HOME}/.local/bin/hermes" 2>/dev/null \
      || ln -sfn /usr/local/bin/hermes "${HOME}/.local/bin/hermes" 2>/dev/null || true
  fi
fi

check "hermes on PATH" command -v hermes >/dev/null
check "docker info" docker info >/dev/null 2>&1
check "Hermes .env" test -f "$HERMES_HOME/.env"
check "Hermes config.yaml" test -f "$HERMES_HOME/config.yaml"
check "USER.md seed" test -s "$HERMES_HOME/memories/USER.md"
if [[ -s "$HERMES_HOME/CV.md" ]]; then
  log "OK  CV.md seed ($HERMES_HOME/CV.md)"
else
  warn "CV.md missing (optional — add artifacts/CV.md and ./scripts/deploy.sh --artifacts)"
fi

# Timezone (optional but recommended via TIMEZONE= in Mac .env)
want_tz=""
if [[ -f "$HERMES_HOME/.env" ]]; then
  want_tz="$(grep -E '^TIMEZONE=' "$HERMES_HOME/.env" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '"' || true)"
fi
cur_tz="$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || true)"
if [[ -n "$want_tz" ]]; then
  if [[ "$cur_tz" == "$want_tz" ]]; then
    log "OK  timezone $cur_tz"
  else
    warn "timezone is '$cur_tz' (want TIMEZONE=$want_tz) — re-run deploy"
  fi
elif [[ -n "$cur_tz" ]]; then
  log "OK  timezone $cur_tz (TIMEZONE not pinned in .env)"
fi

# Self-heal Docker colon-in-path patch after hermes update overwrites docker.py
docker_py=""
for f in \
  /usr/local/lib/hermes-agent/tools/environments/docker.py \
  "${HOME}/.hermes/hermes-agent/tools/environments/docker.py"
do
  [[ -f "$f" ]] && docker_py="$f" && break
done
if [[ -n "$docker_py" ]]; then
  if grep -Fq '_sanitize_label_value(task_id)' "$docker_py" \
    && grep -Fq 'get_sandbox_dir() / "docker"' "$docker_py"; then
    log "OK  Docker path sanitize patch"
  else
    warn "Docker path sanitize missing — re-applying"
    if bash "$SCRIPT_DIR/patch-hermes-docker.sh"; then
      log "OK  Docker path sanitize patch (re-applied)"
    else
      warn "FAIL Docker path sanitize patch"
      failed=1
    fi
  fi
else
  warn "docker.py not found (skip patch check)"
fi

if command -v hermes >/dev/null 2>&1; then
  if hermes doctor >/dev/null 2>&1; then
    log "OK  hermes doctor"
  else
    warn "hermes doctor reported issues (non-fatal; gateway may still be fine)"
    hermes doctor 2>&1 | tail -20 || true
  fi
  if hermes gateway status >/dev/null 2>&1; then
    log "OK  gateway status"
    hermes gateway status || true
  else
    warn "gateway status failed"
    hermes gateway status || true
    # Accept running process as soft OK
    if pgrep -af 'hermes.*gateway' >/dev/null 2>&1; then
      log "OK  gateway process found"
    else
      failed=1
    fi
  fi
fi

# Firecrawl lite (optional but default on full deploy)
if curl -fsS --max-time 3 "http://127.0.0.1:3002/v0/health/readiness" >/dev/null 2>&1; then
  log "OK  Firecrawl API http://127.0.0.1:3002"
else
  warn "Firecrawl not reachable on :3002 (run ./scripts/deploy.sh --firecrawl if needed)"
fi

# Mnemosyne side-venv + provider selection
VENV="${MNEMOSYNE_VENV:-$HERMES_HOME/.mnemosyne/venv}"
if [[ -x "$VENV/bin/mnemosyne-hermes" ]]; then
  log "OK  Mnemosyne side-venv present ($VENV)"
  if command -v hermes >/dev/null 2>&1; then
    if hermes memory status 2>&1 | grep -qi 'Provider:.*mnemosyne'; then
      log "OK  memory.provider=mnemosyne"
    else
      warn "Mnemosyne installed but not selected (hermes config set memory.provider mnemosyne)"
    fi
  fi
else
  warn "Mnemosyne side-venv missing (run ./scripts/deploy.sh --mnemosyne)"
fi

# Agent-Reach custom terminal image + skill
AR_IMAGE="${AGENT_REACH_IMAGE:-hermes-terminal:agent-reach}"
if docker image inspect "$AR_IMAGE" >/dev/null 2>&1; then
  log "OK  Agent-Reach image $AR_IMAGE"
  if docker run --rm "$AR_IMAGE" yt-dlp --version >/dev/null 2>&1; then
    log "OK  Agent-Reach image yt-dlp"
  else
    warn "Agent-Reach image missing yt-dlp"
    failed=1
  fi
else
  warn "Agent-Reach image missing (run ./scripts/deploy.sh --agent-reach)"
fi
if [[ -f "$HERMES_HOME/skills/agent-reach/SKILL.md" ]]; then
  log "OK  Agent-Reach skill installed"
else
  warn "Agent-Reach skill missing (~/.hermes/skills/agent-reach/SKILL.md)"
fi
if command -v hermes >/dev/null 2>&1; then
  img="$(hermes config get terminal.docker_image 2>/dev/null || true)"
  if echo "$img" | grep -q 'agent-reach'; then
    log "OK  terminal.docker_image → agent-reach"
  elif [[ -n "$img" ]]; then
    warn "terminal.docker_image is not agent-reach (got: $img)"
  fi
fi

# Notion (optional — only expected when BOTH env vars are set)
notion_key=""
notion_parent=""
if [[ -f "$HERMES_HOME/.env" ]]; then
  notion_key="$(grep -E '^NOTION_API_KEY=.' "$HERMES_HOME/.env" 2>/dev/null | tail -1 | cut -d= -f2- || true)"
  notion_parent="$(grep -E '^NOTION_REPORTS_PARENT_PAGE_ID=.' "$HERMES_HOME/.env" 2>/dev/null | tail -1 | cut -d= -f2- || true)"
fi
if [[ -n "$notion_key" && -n "$notion_parent" ]]; then
  if [[ -f "$HERMES_HOME/skills/notion-reports/SKILL.md" ]]; then
    log "OK  Notion skill installed"
  else
    warn "Notion env complete but skill missing (./scripts/deploy.sh --notion)"
  fi
  if grep -qE '^\s+notion:' "$HERMES_HOME/config.yaml" 2>/dev/null; then
    log "OK  mcp_servers.notion present"
  else
    warn "Notion env complete but mcp_servers.notion missing"
  fi
elif [[ -n "$notion_key" || -n "$notion_parent" ]]; then
  warn "Notion half-configured (need BOTH NOTION_API_KEY and NOTION_REPORTS_PARENT_PAGE_ID) — ignored"
else
  log "OK  Notion not configured (optional)"
fi

if [[ "$failed" -ne 0 ]]; then
  die "healthcheck failed"
fi
log "Healthcheck passed"
