#!/usr/bin/env bash
# Runs ON the VPS. Installs repo artifacts into Hermes paths.
#
# Hermes built-in memory (official):
#   SOUL.md              → $HERMES_HOME/SOUL.md
#   memories/USER.md     → user profile (memory tool target=user)
#   memories/MEMORY.md   → agent notes  (memory tool target=memory)
#
# USER.md / MEMORY.md format is entry-based: entries joined by "\n§\n"
# (see tools/memory_tool.py ENTRY_DELIMITER). Free-form markdown without
# § still loads as a single entry, but § entries match how the agent writes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

PAYLOAD_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ART_DIR="${PAYLOAD_DIR}/artifacts"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"

mkdir -p "$HERMES_HOME/memories"

# Normalize line endings and ensure file ends with a single newline.
_install_text() {
  local src="$1" dest="$2" mode="${3:-600}"
  # strip CR; ensure trailing newline
  python3 - "$src" "$dest" "$mode" <<'PY'
import pathlib, sys, os
src, dest, mode = sys.argv[1], sys.argv[2], int(sys.argv[3], 8)
text = pathlib.Path(src).read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")
text = text.strip() + "\n"
path = pathlib.Path(dest)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(text, encoding="utf-8")
os.chmod(path, mode)
# quick format hint for memory files
if path.name in {"USER.md", "MEMORY.md"}:
    entries = [e.strip() for e in text.split("\n§\n") if e.strip()]
    print(f"  → {path.name}: {len(entries)} entr(y/ies), {len(text)} chars")
PY
}

if [[ -f "$ART_DIR/SOUL.md" ]]; then
  _install_text "$ART_DIR/SOUL.md" "$HERMES_HOME/SOUL.md" 600
  log "Installed $HERMES_HOME/SOUL.md"
else
  warn "No artifacts/SOUL.md — skipped"
fi

if [[ -f "$ART_DIR/USER.md" ]]; then
  _install_text "$ART_DIR/USER.md" "$HERMES_HOME/memories/USER.md" 600
  log "Installed $HERMES_HOME/memories/USER.md (user profile store)"
else
  warn "No artifacts/USER.md — skipped"
fi

if [[ -f "$ART_DIR/MEMORY.md" ]]; then
  _install_text "$ART_DIR/MEMORY.md" "$HERMES_HOME/memories/MEMORY.md" 600
  log "Installed $HERMES_HOME/memories/MEMORY.md (agent notes store)"
else
  warn "No artifacts/MEMORY.md — skipped (optional)"
fi
