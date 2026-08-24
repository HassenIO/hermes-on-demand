#!/usr/bin/env bash
# Runs ON the VPS. Starts Firecrawl lite (extract) + SearXNG (search) and wires Hermes.
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

# Ensure SearXNG secret is not the placeholder
SETTINGS="$FC_DIR/searxng/settings.yml"
if [[ -f "$SETTINGS" ]] && grep -q 'hermes-searxng-change-me' "$SETTINGS" 2>/dev/null; then
  sk="$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | xxd -p)"
  sed -i "s/hermes-searxng-change-me/${sk}/" "$SETTINGS"
fi

cd "$FC_DIR"
docker compose --profile full down --remove-orphans 2>/dev/null || true
docker compose down --remove-orphans 2>/dev/null || true

if [[ "$FC_MODE" == "full" ]]; then
  log "Starting FULL Firecrawl stack (needs ~4GB+ RAM)"
  docker compose --profile full pull
  docker compose --profile full up -d
else
  log "Starting SearXNG + Firecrawl LITE (search + extract)"
  docker compose pull searxng 2>/dev/null || true
  docker compose build lite
  docker compose up -d searxng lite
fi

log "Waiting for Firecrawl API on 127.0.0.1:3002"
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

if [[ "$FC_MODE" != "full" ]]; then
  log "Waiting for SearXNG on 127.0.0.1:8888"
  sok=0
  for _ in $(seq 1 40); do
    if curl -fsS --max-time 5 "http://127.0.0.1:8888/search?q=test&format=json" >/dev/null 2>&1; then
      sok=1
      break
    fi
    sleep 3
  done
  if [[ "$sok" -ne 1 ]]; then
    docker compose logs --tail=80 searxng || true
    warn "SearXNG not ready — Hermes search may fail until it is"
  else
    n="$(curl -fsS --max-time 20 "http://127.0.0.1:8888/search?q=hermes+agent&format=json" \
      | python3 -c 'import sys,json; print(len(json.load(sys.stdin).get("results") or []))' 2>/dev/null || echo 0)"
    log "SearXNG OK ($n results for sample query)"
  fi
fi

log "Smoke scrape"
curl -fsS --max-time 90 -X POST "http://127.0.0.1:3002/v2/scrape" \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com","formats":["markdown"],"timeout":60000}' \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); assert d.get("success") is True, d; print("scrape ok, markdown chars:", len((d.get("data") or {}).get("markdown") or ""))'

log "Smoke search (Firecrawl /v2/search)"
curl -fsS --max-time 45 -X POST "http://127.0.0.1:3002/v2/search" \
  -H 'Content-Type: application/json' \
  -d '{"query":"hermes agent nous","limit":3}' \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); assert d.get("success"), d; w=(d.get("data") or {}).get("web") or []; print("search ok, n=", len(w), "backend=", (d.get("data") or {}).get("backend")); print("first:", (w[0].get("title") if w else "")[:80])' \
  || warn "lite /v2/search smoke failed (SearXNG path may still work for Hermes)"

log "Pointing Hermes at local Firecrawl + SearXNG"
mkdir -p "$HERMES_HOME"
ENV_FILE="$HERMES_HOME/.env"
touch "$ENV_FILE"
chmod 600 "$ENV_FILE"

upsert_env() {
  local key="$1" val="$2"
  if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
  else
    printf '\n%s=%s\n' "$key" "$val" >>"$ENV_FILE"
  fi
}
upsert_env FIRECRAWL_API_URL "http://127.0.0.1:3002"
upsert_env SEARXNG_URL "http://127.0.0.1:8888"

CFG="$HERMES_HOME/config.yaml"
if [[ ! -f "$CFG" ]]; then
  cat >"$CFG" <<'YAML'
web:
  backend: firecrawl
  search_backend: searxng
  extract_backend: firecrawl
YAML
else
  # Ensure web block has split backends (search=searxng, extract=firecrawl)
  python3 - "$CFG" <<'PY'
from pathlib import Path
import re, sys
p = Path(sys.argv[1])
t = p.read_text()
if not re.search(r"(?m)^web:\s*$", t):
    t = t.rstrip() + "\n\nweb:\n  backend: firecrawl\n  search_backend: searxng\n  extract_backend: firecrawl\n"
else:
    m = re.search(r"(?ms)^web:\n(.*?)(?=^[a-zA-Z_]|\Z)", t)
    if m:
        start, stop = m.start(), m.end()
        before, block, after = t[:start], t[start:stop], t[stop:]
        def set_key(block, key, val):
            if re.search(rf"(?m)^\s+{key}:\s*", block):
                return re.sub(rf"(?m)^(\s+{key}:\s*).*$", rf"\1{val}", block, count=1)
            return block.rstrip() + f"\n  {key}: {val}\n"
        block = set_key(block, "backend", "firecrawl")
        block = set_key(block, "search_backend", "searxng")
        block = set_key(block, "extract_backend", "firecrawl")
        if not block.endswith("\n"):
            block += "\n"
        t = before + block + after
p.write_text(t if t.endswith("\n") else t + "\n")
print(f"updated web backends in {p}")
PY
fi

export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"
if command -v hermes >/dev/null 2>&1; then
  hermes config set web.backend firecrawl >/dev/null 2>&1 || true
  hermes config set web.search_backend searxng >/dev/null 2>&1 || true
  hermes config set web.extract_backend firecrawl >/dev/null 2>&1 || true
  hermes gateway restart 2>/dev/null || hermes gateway start 2>/dev/null || true
fi

log "Ready:"
log "  extract: FIRECRAWL_API_URL=http://127.0.0.1:3002 (lite)"
log "  search:  SEARXNG_URL=http://127.0.0.1:8888"
log "  config:  web.search_backend=searxng  web.extract_backend=firecrawl"
