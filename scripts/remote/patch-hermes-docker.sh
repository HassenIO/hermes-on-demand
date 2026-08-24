#!/usr/bin/env bash
# Runs ON the VPS. Fixes Hermes Docker sandbox paths for Telegram session IDs.
#
# Bug: task_id like "session:agent:main:telegram:dm:123" is used as a host
# directory name in -v mounts. Docker treats ":" as volume syntax → exit 125
# "too many colons". Labels were already sanitized; filesystem paths were not.
#
# Idempotent. Safe to run after every hermes update / deploy / healthcheck.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

CANDIDATES=(
  "/usr/local/lib/hermes-agent/tools/environments/docker.py"
  "${HOME}/.hermes/hermes-agent/tools/environments/docker.py"
)

OLD='sandbox = get_sandbox_dir() / "docker" / task_id'
NEW='sandbox = get_sandbox_dir() / "docker" / _sanitize_label_value(task_id)'

is_patched() {
  local f="$1"
  [[ -f "$f" ]] && grep -Fq '_sanitize_label_value(task_id)' "$f" \
    && grep -Fq 'get_sandbox_dir() / "docker"' "$f"
}

needs_patch() {
  local f="$1"
  [[ -f "$f" ]] && grep -Fq "$OLD" "$f"
}

patched_any=0
found_any=0
for f in "${CANDIDATES[@]}"; do
  [[ -f "$f" ]] || continue
  found_any=1
  if is_patched "$f"; then
    log "Docker path sanitize already present: $f"
    patched_any=1
    continue
  fi
  if ! needs_patch "$f"; then
    warn "docker.py pattern not found (upstream may have changed): $f"
    continue
  fi
  python3 - "$f" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
t = p.read_text()
old = 'sandbox = get_sandbox_dir() / "docker" / task_id'
new = 'sandbox = get_sandbox_dir() / "docker" / _sanitize_label_value(task_id)'
if new in t:
    print(f"ok already: {p}")
    raise SystemExit(0)
if old not in t:
    print(f"skip (pattern missing): {p}")
    raise SystemExit(1)
p.write_text(t.replace(old, new, 1))
print(f"patched: {p}")
PY
  patched_any=1
done

if [[ "$found_any" -eq 0 ]]; then
  warn "docker.py not found — skip path sanitize patch"
  exit 0
fi

if [[ "$patched_any" -eq 1 ]]; then
  log "Hermes Docker sandbox path sanitize OK"
  exit 0
fi

die "Could not apply Docker path sanitize (upstream docker.py shape changed?)"
