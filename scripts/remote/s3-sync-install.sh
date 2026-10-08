#!/usr/bin/env bash
# Runs ON the VPS. Install and start the skills/cron S3 watcher, or stop it
# when AWS/S3 env is incomplete.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

PAYLOAD_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REMOTE_ENV="${REMOTE_ENV:-$PAYLOAD_DIR/remote.env}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
UNIT="hermes-s3-sync.service"
WATCH="$SCRIPT_DIR/s3-sync-watch.sh"

if [[ -f "$REMOTE_ENV" ]]; then
  load_dotenv "$REMOTE_ENV"
elif [[ -f "$HERMES_HOME/.env" ]]; then
  load_dotenv "$HERMES_HOME/.env"
fi

stop_units() {
  if [[ -n "${XDG_RUNTIME_DIR:-}" && -S "${XDG_RUNTIME_DIR}/bus" ]]; then
    systemctl --user disable --now "$UNIT" 2>/dev/null || true
  fi
  sudo systemctl disable --now "$UNIT" 2>/dev/null || true
}

if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" || -z "${AWS_DEFAULT_REGION:-}" || -z "${S3_BUCKET:-}" ]]; then
  log "S3 snapshot env incomplete — stopping watcher if present"
  stop_units
  exit 0
fi

[[ -x "$WATCH" ]] || die "missing $WATCH"

if ! command -v inotifywait >/dev/null 2>&1; then
  log "Installing inotify-tools"
  sudo apt-get update -y
  sudo apt-get install -y inotify-tools
fi
command -v inotifywait >/dev/null 2>&1 || die "inotifywait not on PATH after install"

write_unit() {
  local wanted="$1"
  local user_lines="$2"
  cat <<EOF
[Unit]
Description=Hermes S3 sync for skills and cron
After=network-online.target

[Service]
Type=simple
${user_lines}Environment=HOME=$HOME
Environment=HERMES_HOME=$HERMES_HOME
Environment=REMOTE_ENV=$REMOTE_ENV
ExecStart=$WATCH
Restart=on-failure
RestartSec=5

[Install]
WantedBy=${wanted}
EOF
}

start_user_unit() {
  local uid runtime
  uid="$(id -u)"
  runtime="/run/user/$uid"
  export XDG_RUNTIME_DIR="$runtime"
  if command -v loginctl >/dev/null 2>&1; then
    loginctl enable-linger "$USER" 2>/dev/null || sudo loginctl enable-linger "$USER" 2>/dev/null || true
  fi
  local _
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -S "$runtime/bus" ]] && break
    sleep 1
  done
  [[ -S "$runtime/bus" ]] || return 1
  mkdir -p "$HOME/.config/systemd/user"
  write_unit default.target "" >"$HOME/.config/systemd/user/$UNIT"
  systemctl --user daemon-reload
  systemctl --user enable --now "$UNIT"
  sudo systemctl disable --now "$UNIT" 2>/dev/null || true
}

start_system_unit() {
  local group
  group="$(id -gn)"
  write_unit multi-user.target "User=$USER
Group=$group
" | sudo tee "/etc/systemd/system/$UNIT" >/dev/null
  sudo systemctl daemon-reload
  sudo systemctl enable --now "$UNIT"
}

if start_user_unit; then
  log "S3 watcher running (systemd user $UNIT)"
else
  warn "user systemd bus unavailable — installing system unit"
  start_system_unit
  log "S3 watcher running (systemd system $UNIT)"
fi
