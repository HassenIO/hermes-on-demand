#!/usr/bin/env bash
# Runs ON the VPS. Installs repo artifacts into Hermes paths.
#
# Hermes built-in memory (official):
#   SOUL.md              → $HERMES_HOME/SOUL.md
#   memories/USER.md     → user profile (memory tool target=user)
#   memories/MEMORY.md   → agent notes  (memory tool target=memory)
#
# Extra profile docs (on-demand read, not auto-injected every turn):
#   CV.md                → $HERMES_HOME/CV.md
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
  python3 - "$src" "$dest" "$mode" <<'PY'
import pathlib, sys, os
src, dest, mode = sys.argv[1], sys.argv[2], int(sys.argv[3], 8)
text = pathlib.Path(src).read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")
text = text.strip() + "\n"
path = pathlib.Path(dest)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(text, encoding="utf-8")
os.chmod(path, mode)
if path.name in {"USER.md", "MEMORY.md"}:
    entries = [e.strip() for e in text.split("\n§\n") if e.strip()]
    print(f"  → {path.name}: {len(entries)} entr(y/ies), {len(text)} chars")
elif path.name == "CV.md":
    print(f"  → CV.md: {len(text)} chars → {path}")
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

# Full CV: on-disk reference (not forced into every system prompt)
if [[ -f "$ART_DIR/CV.md" ]]; then
  _install_text "$ART_DIR/CV.md" "$HERMES_HOME/CV.md" 600
  log "Installed $HERMES_HOME/CV.md (read on demand for freelancing/role-fit)"
else
  warn "No artifacts/CV.md — skipped (optional)"
fi

# Ensure Docker sandbox can read CV.md (host path; root install uses /root/.hermes)
_ensure_cv_volume() {
  local cfg="$HERMES_HOME/config.yaml"
  [[ -f "$cfg" ]] || return 0
  local mount="${HERMES_HOME}/CV.md:${HERMES_HOME}/CV.md:ro"
  python3 - "$cfg" "$mount" <<'PY'
from pathlib import Path
import re, sys
cfg_path, mount = Path(sys.argv[1]), sys.argv[2]
text = cfg_path.read_text()
if mount in text or f'"{mount}"' in text:
    print(f"  docker volume already has CV.md")
    raise SystemExit(0)
m = re.search(r"(?ms)^terminal:\n(.*?)(?=^[a-zA-Z_]|\Z)", text)
if not m:
    print("  no terminal block — skip CV volume")
    raise SystemExit(0)
start, stop = m.start(), m.end()
before, block, after = text[:start], text[start:stop], text[stop:]
line = f'    - "{mount}"\n'
if re.search(r"(?ms)^\s+docker_volumes:\n(?:\s+-\s*.*\n)*", block):
    block = re.sub(
        r"(?ms)^(\s+docker_volumes:\n(?:\s+-\s*.*\n)*)",
        lambda m: m.group(1) + line,
        block,
        count=1,
    )
else:
    block = block.rstrip() + "\n  docker_volumes:\n" + line
if not block.endswith("\n"):
    block += "\n"
cfg_path.write_text(before + block + after)
print(f"  added docker volume {mount}")
PY
}
_ensure_cv_volume

# Best-effort: seed Mnemosyne pointer (if installed)
VENV="${MNEMOSYNE_VENV:-$HERMES_HOME/.mnemosyne/venv}"
if [[ -x "$VENV/bin/mnemosyne" ]]; then
  log "Seeding Mnemosyne CV pointer"
  "$VENV/bin/mnemosyne" store \
    "Hassen's full professional CV is on disk at ${HERMES_HOME}/CV.md. Read that file for freelancing, opportunity matching, or detailed career history. Do not invent CV details." \
    2>/dev/null || warn "mnemosyne store CV pointer failed (non-fatal)"
fi
