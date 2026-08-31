#!/usr/bin/env bash
# Run on VPS: install jobs.json into ~/.hermes/cron via Hermes save_jobs API.
# Usage: install-cron-jobs.sh /path/to/jobs.json
# Backs up the previous file, validates shape, replace=True (local is source of truth).
set -euo pipefail

SRC="${1:?jobs.json path required}"
export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
CRON_DIR="$HERMES_HOME/cron"
DEST="$CRON_DIR/jobs.json"

[[ -f "$SRC" ]] || { echo "ERROR: missing $SRC" >&2; exit 1; }

# Prefer Hermes venv so `import cron.jobs` works
PY=""
for cand in \
  /usr/local/lib/hermes-agent/venv/bin/python \
  "${HERMES_HOME}/venv/bin/python" \
  "$(command -v python3 || true)"
do
  if [[ -n "$cand" && -x "$cand" ]]; then
    if "$cand" -c "import cron.jobs" 2>/dev/null; then
      PY="$cand"
      break
    fi
  fi
done
[[ -n "$PY" ]] || { echo "ERROR: no python with cron.jobs importable" >&2; exit 1; }

mkdir -p "$CRON_DIR"
chmod 700 "$CRON_DIR" 2>/dev/null || true

if [[ -f "$DEST" ]]; then
  ts="$(date +%Y%m%dT%H%M%S)"
  cp -a "$DEST" "$CRON_DIR/jobs.json.bak.${ts}"
  # keep last 5 backups
  ls -1t "$CRON_DIR"/jobs.json.bak.* 2>/dev/null | tail -n +6 | xargs -r rm -f
  echo "backup $CRON_DIR/jobs.json.bak.${ts}"
fi

"$PY" - "$SRC" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

src = Path(sys.argv[1])
raw = json.loads(src.read_text(encoding="utf-8-sig"))

if isinstance(raw, dict):
    jobs = raw.get("jobs", [])
elif isinstance(raw, list):
    jobs = raw
else:
    raise SystemExit(f"unexpected jobs.json shape: {type(raw)}")

if not isinstance(jobs, list):
    raise SystemExit("jobs must be a list")

norm = []
seen = set()
for i, j in enumerate(jobs):
    if not isinstance(j, dict):
        raise SystemExit(f"job[{i}] is not an object")
    jid = j.get("id")
    if not jid or not isinstance(jid, str):
        raise SystemExit(f"job[{i}] missing string id")
    if jid in seen:
        raise SystemExit(f"duplicate job id: {jid}")
    seen.add(jid)
    if "name" not in j or not str(j.get("name") or "").strip():
        raise SystemExit(f"job {jid}: missing name")
    if "schedule" not in j or not isinstance(j.get("schedule"), dict):
        raise SystemExit(f"job {jid}: missing schedule object")
    # prompt optional for no_agent/script jobs; keep as-is
    job = dict(j)
    # Clear in-flight fire claims — stale claims after offline edit can block runs
    job["fire_claim"] = None
    norm.append(job)

from cron.jobs import save_jobs, load_jobs, _normalize_job_record

normalized = [_normalize_job_record(j) for j in norm]
save_jobs(normalized, replace=True)

live = load_jobs()
print(f"installed {len(live)} job(s)")
for j in live:
    en = "on" if j.get("enabled", True) else "off"
    sched = j.get("schedule_display") or (j.get("schedule") or {}).get("expr") or "?"
    print(
        f"  [{en}] {j.get('id')}  {j.get('name')}  "
        f"schedule={sched}  model={j.get('model') or 'default'}  "
        f"skill={j.get('skill') or '-'}"
    )
PY
