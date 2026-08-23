#!/usr/bin/env bash
# Runs ON the VPS. Starts Firecrawl-compatible API on localhost:3002 and wires Hermes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

PAYLOAD_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
FC_DIR="${PAYLOAD_DIR}/firecrawl"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
# lite (default) | full
FC_MODE="${FIRECRAWL_MODE:-lite}"

[[ -d "$FC_DIR" ]] || die "missing $FC_DIR"
command -v docker >/dev/null 2>&1 || die "docker required"

if [[ ! -f "$FC_DIR/.env" ]]; then
  if [[ -f "$FC_DIR/.env.example" ]]; then
    pw="$(openssl rand -hex 24 2>/dev/null || head -c 24 /dev/urandom | xxd -p)"
    sed "s/change-me-to-a-long-random-string/${pw}/" "$FC_DIR/.env.example" >"$FC_DIR/.env"
    chmod 600 "$FC_DIR/.env"
    log "Created $FC_DIR/.env"
  else
    printf 'POSTGRES_USER=postgres\nPOSTGRES_PASSWORD=%s\nPOSTGRES_DB=postgres\n' \
      "$(openssl rand -hex 24 2>/dev/null || echo localdevpasswordlocaldevpassword)" \
      >"$FC_DIR/.env"
    chmod 600 "$FC_DIR/.env"
  fi
fi

# Free RAM: stop any previous full stack that may be thrashing
cd "$FC_DIR"
docker compose --profile full down --remove-orphans 2>/dev/null || true
docker compose down --remove-orphans 2>/dev/null || true

if [[ "$FC_MODE" == "full" ]]; then
  log "Starting FULL Firecrawl stack (needs ~4GB+ RAM)"
  docker compose --profile full pull
  docker compose --profile full up -d
else
  log "Starting Firecrawl LITE (Hermes-compatible /v2/scrape + /v2/search)"
  docker compose build lite
  docker compose up -d lite
fi

log "Waiting for API on 127.0.0.1:3002"
ok=0
for _ in $(seq 1 60); do
  if curl -fsS --max-time 3 "http://127.0.0.1:3002/v0/health/readiness" >/dev/null 2>&1; then
    ok=1
    break
  fi
  sleep 3
done
if [[ "$ok" -ne 1 ]]; then
  docker compose ps -a
  docker compose logs --tail=100
  die "Firecrawl API did not become ready"
fi
curl -fsS "http://127.0.0.1:3002/v0/health/readiness"
echo

log "Smoke scrape"
curl -fsS --max-time 90 -X POST "http://127.0.0.1:3002/v2/scrape" \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com","formats":["markdown"],"timeout":60000}' \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); assert d.get("success") is True, d; print("scrape ok, markdown chars:", len((d.get("data") or {}).get("markdown") or ""))'

log "Pointing Hermes at local Firecrawl"
mkdir -p "$HERMES_HOME"
ENV_FILE="$HERMES_HOME/.env"
touch "$ENV_FILE"
chmod 600 "$ENV_FILE"
if grep -q '^FIRECRAWL_API_URL=' "$ENV_FILE" 2>/dev/null; then
  sed -i 's|^FIRECRAWL_API_URL=.*|FIRECRAWL_API_URL=http://127.0.0.1:3002|' "$ENV_FILE"
else
  printf '\nFIRECRAWL_API_URL=http://127.0.0.1:3002\n' >>"$ENV_FILE"
fi

CFG="$HERMES_HOME/config.yaml"
if [[ -f "$CFG" ]]; then
  if grep -qE '^\s*backend:\s*firecrawl\s*$' "$CFG"; then
    :
  elif grep -q '^web:' "$CFG"; then
    if grep -qE '^\s+backend:' "$CFG"; then
      sed -i 's|^\(\s*backend:\).*|\1 firecrawl|' "$CFG"
    else
      awk 'BEGIN{d=0} /^web:/{print; print "  backend: firecrawl"; d=1; next} {print}' \
        "$CFG" >"${CFG}.tmp" && mv "${CFG}.tmp" "$CFG"
    fi
  else
    printf '\nweb:\n  backend: firecrawl\n' >>"$CFG"
  fi
else
  printf 'web:\n  backend: firecrawl\n' >"$CFG"
fi

export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"
if command -v hermes >/dev/null 2>&1; then
  hermes config set web.backend firecrawl >/dev/null 2>&1 || true
  hermes gateway restart 2>/dev/null || hermes gateway start 2>/dev/null || true
fi

log "Ready: FIRECRAWL_API_URL=http://127.0.0.1:3002 (mode=${FC_MODE})"
