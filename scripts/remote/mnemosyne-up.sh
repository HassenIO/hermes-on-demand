#!/usr/bin/env bash
# Runs ON the VPS. Install Mnemosyne for Hermes via persistent side-venv + wrapper.
#
# Canonical docs:
#   https://github.com/mnemosyne-oss/mnemosyne/blob/main/docs/hermes-integration.md
#   https://github.com/mnemosyne-oss/mnemosyne/blob/main/docs/llm-installation-guide.md (Path A)
#
# Side-venv + wrapper survives Hermes venv rebuilds and `hermes update`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"
export HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
export MNEMOSYNE_DATA_DIR="${MNEMOSYNE_DATA_DIR:-$HERMES_HOME/mnemosyne/data}"

MNEMOSYNE_PROFILE="${MNEMOSYNE_PROFILE:-embeddings}"
case "$MNEMOSYNE_PROFILE" in
  embeddings) MNEMOSYNE_REQUIREMENT="mnemosyne-memory[embeddings]" ;;
  all) MNEMOSYNE_REQUIREMENT="mnemosyne-memory[all]" ;;
  *) die "MNEMOSYNE_PROFILE must be embeddings or all (got: $MNEMOSYNE_PROFILE)" ;;
esac

upsert_env() {
  local key="$1" val="$2" f="${3:-$HERMES_HOME/.env}"
  mkdir -p "$(dirname "$f")"
  touch "$f"
  python3 - "$f" "$key" "$val" <<'PY'
from pathlib import Path
import sys
path, key, val = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
lines = path.read_text().splitlines() if path.exists() else []
out, found = [], False
for line in lines:
    if line.startswith(key + "="):
        out.append(f"{key}={val}")
        found = True
    else:
        out.append(line)
if not found:
    if out and out[-1].strip():
        out.append("")
    out.append(f"{key}={val}")
path.write_text("\n".join(out) + "\n")
PY
  chmod 600 "$f" 2>/dev/null || true
}

# --- Resolve Hermes gateway Python (launcher sibling) ---
HERMES_BIN="$(command -v hermes)" || die "hermes not on PATH"
HERMES_BIN="$(readlink -f "$HERMES_BIN")" || die "could not resolve hermes launcher"
[[ -f "$HERMES_BIN" && -x "$HERMES_BIN" ]] || die "hermes launcher not executable: $HERMES_BIN"
HERMES_BIN_DIR="$(dirname "$HERMES_BIN")"
if [[ -x "$HERMES_BIN_DIR/python" ]]; then
  HERMES_PYTHON="$HERMES_BIN_DIR/python"
elif [[ -x "$HERMES_BIN_DIR/python3" ]]; then
  HERMES_PYTHON="$HERMES_BIN_DIR/python3"
elif [[ -x /usr/local/lib/hermes-agent/venv/bin/python ]]; then
  HERMES_PYTHON=/usr/local/lib/hermes-agent/venv/bin/python
elif [[ -x "${HOME}/.hermes/hermes-agent/venv/bin/python" ]]; then
  HERMES_PYTHON="${HOME}/.hermes/hermes-agent/venv/bin/python"
else
  die "Could not find Hermes Python beside $HERMES_BIN"
fi
"$HERMES_PYTHON" --version >/dev/null || die "Hermes Python failed: $HERMES_PYTHON"
log "Hermes Python: $HERMES_PYTHON ($("$HERMES_PYTHON" --version 2>&1))"

VENV="${MNEMOSYNE_VENV:-$HERMES_HOME/.mnemosyne/venv}"
mkdir -p "$(dirname "$VENV")" "$MNEMOSYNE_DATA_DIR"

if [[ ! -x "$VENV/bin/python" ]]; then
  log "Creating Mnemosyne side venv at $VENV"
  "$HERMES_PYTHON" -m venv "$VENV"
fi

log "Installing $MNEMOSYNE_REQUIREMENT + mnemosyne-hermes into side venv"
"$VENV/bin/python" -m pip install --upgrade pip
"$VENV/bin/python" -m pip install --upgrade "$MNEMOSYNE_REQUIREMENT" mnemosyne-hermes

log "Registering Hermes plugin (wrapper mode)"
[[ -x "$VENV/bin/mnemosyne-hermes" ]] || die "mnemosyne-hermes missing from side venv"
"$VENV/bin/mnemosyne-hermes" install --mode wrapper --python "$VENV/bin/python" --force
"$VENV/bin/mnemosyne-hermes" status || true

# Env for data dir + optional remote embeddings (OpenRouter)
upsert_env "HERMES_HOME" "$HERMES_HOME"
upsert_env "MNEMOSYNE_DATA_DIR" "$MNEMOSYNE_DATA_DIR"

OR_KEY=""
if [[ -f "$HERMES_HOME/.env" ]]; then
  OR_KEY="$(python3 - <<'PY'
from pathlib import Path
import os
p = Path(os.environ["HERMES_HOME"]) / ".env"
for line in p.read_text().splitlines():
    if line.startswith("OPENROUTER_API_KEY="):
        print(line.split("=", 1)[1].strip().strip('"').strip("'"))
        break
PY
)"
fi
if [[ -n "$OR_KEY" ]]; then
  log "Configuring remote embeddings via OpenRouter (saves RAM on small VPS)"
  upsert_env "MNEMOSYNE_EMBEDDING_API_URL" "https://openrouter.ai/api/v1"
  upsert_env "MNEMOSYNE_EMBEDDING_API_KEY" "$OR_KEY"
  upsert_env "MNEMOSYNE_EMBEDDING_MODEL" \
    "${MNEMOSYNE_EMBEDDING_MODEL:-openai/text-embedding-3-small}"
fi

log "Setting memory.provider=mnemosyne"
hermes config set memory.provider mnemosyne 2>/dev/null || true

# Never let memory provider leak into model.provider
hermes config set model.provider openrouter 2>/dev/null || true
hermes config set memory.provider mnemosyne 2>/dev/null || true

python3 - <<'PY'
"""Set Mnemosyne as default memory provider; disable built-in injection."""
from pathlib import Path
import os, re

p = Path(os.environ.get("HERMES_HOME", str(Path.home() / ".hermes"))) / "config.yaml"
text = p.read_text() if p.exists() else ""

# Guard: model.provider must remain an LLM provider
text = re.sub(
    r"(?m)^(model:\n(?:  [^\n]*\n)*?  provider:\s*)mnemosyne\s*$",
    r"\1openrouter",
    text,
)

mem_block = """memory:
  provider: mnemosyne
  memory_enabled: false
  user_profile_enabled: false
  memory_char_limit: 2200
  user_char_limit: 1375
  write_approval: false
"""

if re.search(r"(?m)^memory:\s*$", text):
    # Replace entire memory: section through next top-level key or EOF
    text = re.sub(
        r"(?ms)^memory:\n(?:  [^\n]*\n?)*",
        mem_block if mem_block.endswith("\n") else mem_block + "\n",
        text,
        count=1,
    )
else:
    text = text.rstrip() + "\n\n" + mem_block

p.write_text(text if text.endswith("\n") else text + "\n")
print(f"updated {p}")
PY

# Seed from artifacts USER.md
ART_USER="$(cd "$SCRIPT_DIR/../.." && pwd)/artifacts/USER.md"
if [[ -f "$ART_USER" && -x "$VENV/bin/mnemosyne" ]]; then
  log "Seeding Mnemosyne from artifacts/USER.md"
  python3 - <<PY
from pathlib import Path
import subprocess, os
user = Path("$ART_USER").read_text(encoding="utf-8")
entries = [e.strip() for e in user.split("\n§\n") if e.strip()]
mn = "$VENV/bin/mnemosyne"
env = os.environ.copy()
env["MNEMOSYNE_DATA_DIR"] = "$MNEMOSYNE_DATA_DIR"
env["HERMES_HOME"] = "$HERMES_HOME"
for e in entries:
    r = subprocess.run([mn, "store", e], env=env, capture_output=True, text=True)
    tag = "OK" if r.returncode == 0 else "WARN"
    extra = (r.stderr or r.stdout or "").strip()[:100]
    print(tag, e[:70], extra)
print(f"seeded {len(entries)} entries")
PY
fi

log "Restarting gateway"
hermes gateway restart 2>/dev/null || hermes gateway start 2>/dev/null || true
sleep 5

log "Status"
hermes memory status 2>&1 || true
"$VENV/bin/mnemosyne" stats 2>&1 || true
hermes tools list 2>&1 | grep -i mnemosyne | head -25 || true

log "Mnemosyne install complete (side-venv: $VENV)"
