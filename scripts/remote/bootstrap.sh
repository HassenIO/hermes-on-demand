#!/usr/bin/env bash
# Runs ON the VPS. Idempotent Hermes + Docker + Telegram gateway setup.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

PAYLOAD_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REMOTE_ENV="${PAYLOAD_DIR}/remote.env"
CONFIG_SRC="${PAYLOAD_DIR}/config/config.yaml.example"

export DEBIAN_FRONTEND=noninteractive
export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"

if [[ "$(uname -s)" != "Linux" ]]; then
  die "bootstrap is for Linux VPS only (got $(uname -s))"
fi

log "Installing base packages"
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y \
    ca-certificates curl git xz-utils ffmpeg gnupg lsb-release \
    apt-transport-https software-properties-common
else
  die "expected apt-get (Ubuntu/Debian)"
fi

log "Ensuring Docker"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sudo sh
fi
sudo systemctl enable --now docker
if [[ "$(id -u)" -ne 0 ]]; then
  sudo usermod -aG docker "$USER" || true
fi
docker info >/dev/null

log "Ensuring Hermes Agent"
export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"
if ! command -v hermes >/dev/null 2>&1 \
  && [[ ! -x /usr/local/lib/hermes-agent/venv/bin/hermes ]] \
  && [[ ! -x "${HOME}/.hermes/hermes-agent/venv/bin/hermes" ]]; then
  # VPS gateway uses Docker sandbox / no local Chromium. Skip Playwright browser
  # install so the official installer does not hang on large downloads.
  # Docs: https://hermes-agent.nousresearch.com/docs/getting-started/installation
  log "Running official installer (--skip-browser)"
  set +e
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-browser
  install_rc=$?
  set -e
  if [[ "$install_rc" -ne 0 ]]; then
    warn "official installer exited $install_rc — attempting partial recovery"
  fi
fi

# Always repair CLI links to the real venv entrypoint (never a self-loop)
_link_hermes_cli() {
  local venv_hermes=""
  if [[ -x /usr/local/lib/hermes-agent/venv/bin/hermes ]]; then
    venv_hermes=/usr/local/lib/hermes-agent/venv/bin/hermes
  elif [[ -x "${HOME}/.hermes/hermes-agent/venv/bin/hermes" ]]; then
    venv_hermes="${HOME}/.hermes/hermes-agent/venv/bin/hermes"
  fi
  [[ -n "$venv_hermes" ]] || return 1
  ln -sfn "$venv_hermes" /usr/local/bin/hermes 2>/dev/null || true
  mkdir -p "${HOME}/.local/bin"
  # Break self-referential loops from prior broken doctor --fix runs
  if [[ -L "${HOME}/.local/bin/hermes" ]]; then
    local t
    t="$(readlink "${HOME}/.local/bin/hermes" 2>/dev/null || true)"
    if [[ "$t" == "${HOME}/.local/bin/hermes" || "$t" == "hermes" || "$t" == "./hermes" ]]; then
      rm -f "${HOME}/.local/bin/hermes"
    fi
  fi
  ln -sfn "$venv_hermes" "${HOME}/.local/bin/hermes"
  return 0
}
_link_hermes_cli || true
hash -r 2>/dev/null || true
command -v hermes >/dev/null 2>&1 || die "hermes not on PATH after install"
log "hermes: $(command -v hermes) ($(hermes --version 2>/dev/null | head -1 || true))"

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
mkdir -p "$HERMES_HOME"

[[ -f "$REMOTE_ENV" ]] || die "missing $REMOTE_ENV (deploy must push filtered secrets)"
[[ -f "$CONFIG_SRC" ]] || die "missing $CONFIG_SRC"

log "Writing $HERMES_HOME/.env"
install -m 600 "$REMOTE_ENV" "$HERMES_HOME/.env"

log "Writing $HERMES_HOME/config.yaml"
install -m 644 "$CONFIG_SRC" "$HERMES_HOME/config.yaml"

# Persona + user profile from repo artifacts/
if [[ -f "$SCRIPT_DIR/install-artifacts.sh" ]]; then
  bash "$SCRIPT_DIR/install-artifacts.sh"
fi

# Telegram session IDs contain ":" which breaks Docker -v paths (exit 125)
if [[ -f "$SCRIPT_DIR/patch-hermes-docker.sh" ]]; then
  bash "$SCRIPT_DIR/patch-hermes-docker.sh"
fi

# Ensure OpenRouter + model via CLI when available (best-effort; files are source of truth)
if hermes config set model.provider openrouter >/dev/null 2>&1; then
  hermes config set model.default xiaomi/mimo-v2.5 >/dev/null 2>&1 || true
  hermes config set terminal.backend docker >/dev/null 2>&1 || true
fi

log "Installing gateway service (user unit)"
# Root system unit refuses without --run-as-user; user unit + linger is the
# supported path for both root and normal accounts.
hermes gateway install || true

if command -v loginctl >/dev/null 2>&1; then
  if loginctl enable-linger "$USER" 2>/dev/null; then
    log "Linger enabled for $USER"
  elif sudo loginctl enable-linger "$USER" 2>/dev/null; then
    log "Linger enabled for $USER (via sudo)"
  else
    warn "Could not enable linger; gateway may stop on logout"
  fi
fi

log "Pre-pulling Docker terminal image (best-effort)"
if command -v docker >/dev/null 2>&1; then
  img="$(python3 - <<'PY' 2>/dev/null || true
import re, pathlib
p = pathlib.Path.home() / ".hermes" / "config.yaml"
text = p.read_text() if p.exists() else ""
m = re.search(r'docker_image:\s*["\']?([^"\'\n]+)', text)
print(m.group(1).strip() if m else "nikolaik/python-nodejs:python3.11-nodejs20")
PY
)"
  img="${img:-nikolaik/python-nodejs:python3.11-nodejs20}"
  docker pull "$img" || warn "docker pull $img failed (gateway can pull later)"
fi

log "Starting gateway"
hermes gateway restart 2>/dev/null || hermes gateway start 2>/dev/null || {
  # Foreground probe if service helpers fail
  warn "service start helpers failed; trying hermes gateway in background"
  nohup hermes gateway >>"$HERMES_HOME/logs/gateway.nohup.log" 2>&1 &
  sleep 2
}

log "Bootstrap finished"
hermes gateway status 2>/dev/null || true
