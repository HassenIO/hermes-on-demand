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

if [[ "$failed" -ne 0 ]]; then
  die "healthcheck failed"
fi
log "Healthcheck passed"
