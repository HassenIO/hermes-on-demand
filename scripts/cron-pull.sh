#!/usr/bin/env bash
# Pull Hermes scheduled cron jobs from the VPS into ./cron/
# Local control plane only — never installs Hermes locally.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/scripts/lib/common.sh"

load_dotenv "$ROOT/.env"
require_vars TARGET_HOST TARGET_USER

SSH_PORT="${SSH_PORT:-22}"
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -p "$SSH_PORT")
if [[ -n "${SSH_IDENTITY_FILE:-}" ]]; then
  SSH_OPTS+=(-i "$SSH_IDENTITY_FILE")
fi

ssh_cmd() {
  ssh "${SSH_OPTS[@]}" "${TARGET_USER}@${TARGET_HOST}" "$@"
}

scp_cmd() {
  scp -P "$SSH_PORT" ${SSH_IDENTITY_FILE:+-i "$SSH_IDENTITY_FILE"} \
    -o StrictHostKeyChecking=accept-new "$@"
}

DEST="${ROOT}/cron"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/hermes-cron-pull.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

log "SSH probe ${TARGET_USER}@${TARGET_HOST}:${SSH_PORT}"
ssh_cmd "true"

# Resolve remote HERMES_HOME/cron/jobs.json
REMOTE_JOBS="$(ssh_cmd 'python3 - <<'"'"'PY'"'"'
import os
from pathlib import Path
home = Path(os.environ.get("HERMES_HOME") or Path.home() / ".hermes")
p = home / "cron" / "jobs.json"
print(p if p.is_file() else "")
PY
')"

if [[ -z "$REMOTE_JOBS" ]]; then
  die "remote jobs.json not found (expected ~/.hermes/cron/jobs.json)"
fi

log "Fetching $REMOTE_JOBS"
scp_cmd "${TARGET_USER}@${TARGET_HOST}:${REMOTE_JOBS}" "$STAGING/jobs.json"

# Validate JSON + write pretty-printed copy; keep full job records (ids, prompts,
# schedule, model pins, origin, runtime fields) so a later push can round-trip.
python3 - "$STAGING/jobs.json" "$DEST" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dest_dir = Path(sys.argv[2])
dest_dir.mkdir(parents=True, exist_ok=True)

raw = json.loads(src.read_text(encoding="utf-8"))
if isinstance(raw, dict):
    jobs = raw.get("jobs", [])
    updated = raw.get("updated_at")
elif isinstance(raw, list):
    jobs = raw
    updated = None
    raw = {"jobs": jobs}
else:
    raise SystemExit(f"unexpected jobs.json shape: {type(raw)}")

if not isinstance(jobs, list):
    raise SystemExit("jobs.json 'jobs' is not a list")

out = dest_dir / "jobs.json"
out.write_text(json.dumps(raw, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
out.chmod(0o600)

print(f"jobs={len(jobs)}")
if updated:
    print(f"updated_at={updated}")
for j in jobs:
    jid = j.get("id") or "?"
    name = j.get("name") or "(unnamed)"
    en = "on" if j.get("enabled", True) else "off"
    sched = j.get("schedule_display") or (
        (j.get("schedule") or {}).get("display")
        or (j.get("schedule") or {}).get("expr")
        or "?"
    )
    model = j.get("model") or "default"
    skill = j.get("skill") or "-"
    state = j.get("state") or "-"
    print(f"  [{en}] {jid}  {name}")
    print(f"         schedule={sched}  model={model}  skill={skill}  state={state}")
PY

log "Pulled → $DEST/jobs.json"
