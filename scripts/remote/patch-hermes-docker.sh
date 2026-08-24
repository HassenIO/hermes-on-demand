#!/usr/bin/env bash
# Runs ON the VPS. Fixes Hermes Docker sandbox paths for Telegram session IDs.
#
# Bug: task_id like "session:agent:main:telegram:dm:123" is used as a host
# directory name in -v mounts. Docker treats ":" as volume syntax → exit 125
# "too many colons". Labels were already sanitized; filesystem paths were not.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

CANDIDATES=(
  "/usr/local/lib/hermes-agent/tools/environments/docker.py"
  "${HOME}/.hermes/hermes-agent/tools/environments/docker.py"
)

patched=0
for f in "${CANDIDATES[@]}"; do
  [[ -f "$f" ]] || continue
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
    raise SystemExit(0)
p.write_text(t.replace(old, new, 1))
print(f"patched: {p}")
PY
  patched=1
done

if [[ "$patched" -eq 0 ]]; then
  warn "docker.py not found — skip path sanitize patch"
else
  log "Hermes Docker sandbox path sanitize applied"
fi
