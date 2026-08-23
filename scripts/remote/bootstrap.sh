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
if ! command -v hermes >/dev/null 2>&1; then
  # Official installer can hang a long time on Playwright browser download.
  # Run it with a long timeout; if the CLI lands in the venv, finish the link ourselves.
  set +e
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
  install_rc=$?
  set -e
  if [[ "$install_rc" -ne 0 ]]; then
    warn "official installer exited $install_rc — attempting partial recovery"
  fi
fi

# Root FHS layout: ensure /usr/local/bin/hermes points at the venv entrypoint
if [[ ! -x /usr/local/bin/hermes ]]; then
  if [[ -x /usr/local/lib/hermes-agent/venv/bin/hermes ]]; then
    ln -sfn /usr/local/lib/hermes-agent/venv/bin/hermes /usr/local/bin/hermes
    log "Linked /usr/local/bin/hermes → venv"
  elif [[ -x "${HOME}/.local/bin/hermes" ]]; then
    export PATH="${HOME}/.local/bin:${PATH}"
  fi
fi
# Non-root convenience symlink doctor expects
if [[ -x /usr/local/bin/hermes || -x /usr/local/lib/hermes-agent/venv/bin/hermes ]]; then
  mkdir -p "${HOME}/.local/bin"
  ln -sfn "$(command -v hermes 2>/dev/null || echo /usr/local/lib/hermes-agent/venv/bin/hermes)" \
    "${HOME}/.local/bin/hermes" 2>/dev/null || true
fi
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
