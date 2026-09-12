#!/usr/bin/env bash
# Runs ON the VPS. Pin every Hermes cron job to the current config model/provider.
# Prevents drift_skip when config.yaml model changes after jobs were created unpinned.
#
# Usage (after writing config.yaml):
#   bash scripts/remote/pin-cron-models.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
CFG="$HERMES_HOME/config.yaml"
JOBS_JSON="$HERMES_HOME/cron/jobs.json"

if ! command -v hermes >/dev/null 2>&1; then
  warn "hermes not on PATH — skip cron model pin"
  exit 0
fi

if [[ ! -f "$CFG" ]]; then
  warn "missing $CFG — skip cron model pin"
  exit 0
fi

# Resolve provider + model from config.yaml (Python for reliable YAML)
read -r PROVIDER MODEL < <(python3 - "$CFG" <<'PY'
from pathlib import Path
import sys
try:
    import yaml
except ImportError:
    yaml = None

cfg_path = Path(sys.argv[1])
text = cfg_path.read_text()
provider, model = "openrouter", ""

if yaml is not None:
    data = yaml.safe_load(text) or {}
    m = data.get("model") or {}
    if isinstance(m, dict):
        provider = str(m.get("provider") or provider).strip() or provider
        model = str(m.get("default") or m.get("model") or "").strip()
    elif isinstance(m, str):
        model = m.strip()
else:
    # minimal fallback
    import re
    pm = re.search(r"(?m)^\s+provider:\s*(\S+)", text)
    dm = re.search(r"(?m)^\s+default:\s*(\S+)", text)
    if pm:
        provider = pm.group(1).strip().strip('"').strip("'")
    if dm:
        model = dm.group(1).strip().strip('"').strip("'")

if not model:
    print("MISSING MISSING")
    raise SystemExit(0)
print(provider, model)
PY
)

if [[ -z "${MODEL:-}" || "$MODEL" == "MISSING" ]]; then
  warn "could not read model.default from $CFG — skip cron model pin"
  exit 0
fi

# Pin jobs that are unpinned or already on the config default.
# Skip jobs with an intentional override (e.g. content write model) unless FORCE.
#   PIN_CRON_FORCE=1 bash scripts/remote/pin-cron-models.sh
FORCE="${PIN_CRON_FORCE:-0}"
log "Pinning cron jobs to provider=$PROVIDER model=$MODEL (force=$FORCE; preserve explicit overrides)"

PIN_LINES="$(python3 - "$JOBS_JSON" "$MODEL" "$FORCE" <<'PY'
from pathlib import Path
import json, sys
p = Path(sys.argv[1])
target = (sys.argv[2] or "").strip()
force = sys.argv[3].strip() in ("1", "true", "yes")
if not p.exists():
    raise SystemExit(0)
data = json.loads(p.read_text())
jobs = data.get("jobs") if isinstance(data, dict) else data
if isinstance(jobs, dict):
    jobs = list(jobs.values())
if not isinstance(jobs, list):
    raise SystemExit(0)
for j in jobs:
    if not isinstance(j, dict) or not j.get("id"):
        continue
    jid = j["id"]
    cur = (j.get("model") or "").strip()
    name = (j.get("name") or jid)[:48]
    if force or not cur or cur == target:
        print(f"pin\t{jid}\t{name}")
    else:
        print(f"skip\t{jid}\t{name}\t{cur}")
PY
)"

if [[ -z "${PIN_LINES//[$'\n\r\t ']/}" ]]; then
  log "No cron jobs found — nothing to pin"
  exit 0
fi

pinned=0
skipped=0
failed=0
while IFS=$'\t' read -r action jid name extra; do
  [[ -n "$action" ]] || continue
  if [[ "$action" == "skip" ]]; then
    log "  skip $jid ($name) — keep model=${extra:-?} (override)"
    skipped=$((skipped + 1))
    continue
  fi
  out="$(hermes cron edit "$jid" --provider "$PROVIDER" --model "$MODEL" 2>&1)" && ok=1 || ok=0
  if [[ "$ok" -eq 1 ]]; then
    log "  pinned $jid → $PROVIDER / $MODEL"
    pinned=$((pinned + 1))
  else
    warn "  failed to pin $jid: $(echo "$out" | tail -3 | tr '\n' ' ')"
    failed=$((failed + 1))
  fi
done <<<"$PIN_LINES"

log "Cron pin complete: $pinned pinned, $skipped preserved overrides, $failed failed (target $PROVIDER / $MODEL)"
exit 0
