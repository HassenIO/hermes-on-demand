#!/usr/bin/env bash
# Runs ON the VPS. Apply system timezone from TIMEZONE env (IANA name, e.g. Asia/Dubai).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Prefer explicit env, then Hermes .env, then payload remote.env
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
PAYLOAD_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ -z "${TIMEZONE:-}" && -f "$HERMES_HOME/.env" ]]; then
  # shellcheck disable=SC1090
  set -a
  # only pull TIMEZONE line if present
  TZ_LINE="$(grep -E '^TIMEZONE=' "$HERMES_HOME/.env" 2>/dev/null | tail -1 || true)"
  [[ -n "$TZ_LINE" ]] && eval "$TZ_LINE"
  set +a
fi
if [[ -z "${TIMEZONE:-}" && -f "$PAYLOAD_DIR/remote.env" ]]; then
  TZ_LINE="$(grep -E '^TIMEZONE=' "$PAYLOAD_DIR/remote.env" 2>/dev/null | tail -1 || true)"
  [[ -n "$TZ_LINE" ]] && eval "$TZ_LINE"
fi

TIMEZONE="${TIMEZONE:-}"
if [[ -z "$TIMEZONE" ]]; then
  log "TIMEZONE unset — leaving system timezone unchanged ($(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo unknown))"
  exit 0
fi

# Basic IANA sanity: Area/Location
if [[ ! "$TIMEZONE" =~ ^[A-Za-z0-9_+-]+/[A-Za-z0-9_+/-]+$ ]]; then
  die "invalid TIMEZONE='$TIMEZONE' (expected IANA e.g. Asia/Dubai)"
fi

log "Setting system timezone → $TIMEZONE"

if command -v timedatectl >/dev/null 2>&1; then
  # Ensure tzdata present
  if command -v apt-get >/dev/null 2>&1; then
    if [[ ! -e "/usr/share/zoneinfo/$TIMEZONE" ]]; then
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq >/dev/null 2>&1 || true
      apt-get install -y -qq tzdata >/dev/null 2>&1 || true
    fi
  fi
  if [[ ! -e "/usr/share/zoneinfo/$TIMEZONE" ]]; then
    die "timezone not found on system: $TIMEZONE"
  fi
  timedatectl set-timezone "$TIMEZONE"
elif [[ -e "/usr/share/zoneinfo/$TIMEZONE" ]]; then
  ln -sfn "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
  echo "$TIMEZONE" >/etc/timezone 2>/dev/null || true
else
  die "cannot set timezone (no timedatectl and missing zoneinfo): $TIMEZONE"
fi

# Persist for Hermes process env (cron, logs, agent-relative times)
mkdir -p "$HERMES_HOME"
ENV_FILE="$HERMES_HOME/.env"
touch "$ENV_FILE"
chmod 600 "$ENV_FILE"
if grep -q '^TIMEZONE=' "$ENV_FILE" 2>/dev/null; then
  sed -i "s|^TIMEZONE=.*|TIMEZONE=${TIMEZONE}|" "$ENV_FILE"
else
  printf '\nTIMEZONE=%s\n' "$TIMEZONE" >>"$ENV_FILE"
fi
# Also TZ for libraries that read it
if grep -q '^TZ=' "$ENV_FILE" 2>/dev/null; then
  sed -i "s|^TZ=.*|TZ=${TIMEZONE}|" "$ENV_FILE"
else
  printf 'TZ=%s\n' "$TIMEZONE" >>"$ENV_FILE"
fi

current="$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || readlink /etc/localtime)"
log "Timezone active: $current ($(date '+%Y-%m-%d %H:%M %Z'))"
