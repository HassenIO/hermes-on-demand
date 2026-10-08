#!/usr/bin/env bash
# Runs ON the VPS. Stage custom skills + cron/jobs.json and mirror them to S3.
# Does not upload SQLite, sessions, logs, or secrets.
# Requires AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_DEFAULT_REGION, S3_BUCKET
# in the payload remote.env (or ~/.hermes/.env). Optional S3_PREFIX.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

PAYLOAD_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REMOTE_ENV="${REMOTE_ENV:-$PAYLOAD_DIR/remote.env}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
mkdir -p "$HERMES_HOME/cache"
exec 9>"$HERMES_HOME/cache/s3-snapshot.lock"
flock -w 600 9 || die "timed out waiting for another S3 snapshot"

if [[ -f "$REMOTE_ENV" ]]; then
  load_dotenv "$REMOTE_ENV"
elif [[ -f "$HERMES_HOME/.env" ]]; then
  load_dotenv "$HERMES_HOME/.env"
else
  die "missing $REMOTE_ENV (deploy must push AWS_* and S3_BUCKET)"
fi

require_vars AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION S3_BUCKET

S3_PREFIX="${S3_PREFIX:-hermes/snapshot}"
S3_PREFIX="${S3_PREFIX#/}"
S3_PREFIX="${S3_PREFIX%/}"
[[ -n "$S3_PREFIX" && "$S3_PREFIX" != *..* ]] || die "unsafe S3_PREFIX: ${S3_PREFIX:-<empty>}"

export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION
unset AWS_PROFILE || true

if ! command -v aws >/dev/null 2>&1; then
  log "Installing awscli"
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y
    sudo apt-get install -y awscli
  else
    die "aws CLI not found and apt-get is unavailable"
  fi
fi
command -v aws >/dev/null 2>&1 || die "aws CLI not on PATH after install"

log "Checking s3://${S3_BUCKET}"
aws s3api head-bucket --bucket "$S3_BUCKET" --region "$AWS_DEFAULT_REGION" \
  || die "cannot access s3://${S3_BUCKET} (bucket missing, wrong region, or IAM)"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/hermes-s3-snapshot.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/skills" "$STAGE/cron"

HOME_SKILLS="$HERMES_HOME/skills"
BUILTIN="${HERMES_BUILTIN_SKILLS:-/usr/local/lib/hermes-agent/skills}"
JOBS="$HERMES_HOME/cron/jobs.json"
if [[ -f "$JOBS" ]]; then
  cp -p "$JOBS" "$STAGE/cron/jobs.json"
fi

STATS="$(python3 - "$HOME_SKILLS" "$BUILTIN" "$STAGE/skills" "$JOBS" "$STAGE/manifest.json" <<'PY'
import hashlib
import json
import os
import shutil
import socket
import sys
from datetime import datetime, timezone
from pathlib import Path

home = Path(sys.argv[1]).expanduser()
builtin = Path(sys.argv[2])
stage_skills = Path(sys.argv[3])
jobs = Path(sys.argv[4])
manifest_path = Path(sys.argv[5])

def should_include(path: Path) -> bool:
    name = path.name
    if name.startswith("."):
        return False
    if name == "README.md" or name.endswith(".sha256"):
        return False
    return True

roots: list[Path] = []
if home.is_dir():
    for skill_md in sorted(home.rglob("SKILL.md")):
        rel = skill_md.relative_to(home)
        if builtin.is_dir() and (builtin / rel).exists():
            continue
        roots.append(skill_md.parent.resolve())
roots = sorted(set(roots), key=lambda p: str(p))

copied = 0
for root in roots:
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if should_include(Path(d)))
        for fn in sorted(filenames):
            fp = Path(dirpath) / fn
            if not should_include(fp) or not fp.is_file():
                continue
            rel = fp.relative_to(home)
            dest = stage_skills / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(fp, dest)
            copied += 1

jobs_sha = hashlib.sha256(jobs.read_bytes()).hexdigest() if jobs.is_file() else ""
manifest = {
    "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "hostname": socket.gethostname(),
    "skill_packages": len(roots),
    "skill_files": copied,
    "jobs_sha256": jobs_sha or None,
}
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
print(f"skill_packages={len(roots)}")
print(f"skill_files={copied}")
print(f"jobs_sha256={jobs_sha}")
PY
)"
printf '%s\n' "$STATS" | sed 's/^/  /'

SKILL_PACKAGES="$(printf '%s\n' "$STATS" | sed -n 's/^skill_packages=//p')"
JOBS_SHA="$(printf '%s\n' "$STATS" | sed -n 's/^jobs_sha256=//p')"

DEST="s3://${S3_BUCKET}/${S3_PREFIX}"
SSE_ARGS=(--sse AES256 --region "$AWS_DEFAULT_REGION")

if [[ "${SKILL_PACKAGES:-0}" -gt 0 ]]; then
  log "Syncing custom skills → ${DEST}/skills"
  aws s3 sync "$STAGE/skills" "${DEST}/skills" --delete "${SSE_ARGS[@]}"
else
  warn "no custom skills — leaving ${DEST}/skills unchanged"
fi

if [[ -n "$JOBS_SHA" ]]; then
  log "Uploading cron/jobs.json → ${DEST}/cron/jobs.json"
  aws s3 cp "$STAGE/cron/jobs.json" "${DEST}/cron/jobs.json" "${SSE_ARGS[@]}"
else
  warn "missing $JOBS — leaving remote cron/jobs.json unchanged"
fi

log "Uploading manifest → ${DEST}/manifest.json"
aws s3 cp "$STAGE/manifest.json" "${DEST}/manifest.json" "${SSE_ARGS[@]}"

log "S3 snapshot at ${DEST}"
