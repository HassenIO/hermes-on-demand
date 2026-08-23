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

check "hermes on PATH" command -v hermes >/dev/null
check "docker info" docker info >/dev/null 2>&1
check "Hermes .env" test -f "$HERMES_HOME/.env"
check "Hermes config.yaml" test -f "$HERMES_HOME/config.yaml"

if command -v hermes >/dev/null 2>&1; then
  if hermes doctor >/dev/null 2>&1; then
    log "OK  hermes doctor"
  else
    warn "hermes doctor reported issues (see output below)"
    hermes doctor || true
    failed=1
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

if [[ "$failed" -ne 0 ]]; then
  die "healthcheck failed"
fi
log "Healthcheck passed"
