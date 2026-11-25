#!/usr/bin/env bash
# Runs ON the VPS. Pull the S3 mirror (custom skills + cron/jobs.json) into a
# fresh install. Counterpart of s3-snapshot.sh. Adds only: never deletes local
# state, never overwrites an existing jobs.json, never prunes local skills.
# Requires AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_DEFAULT_REGION, S3_BUCKET
# in the payload remote.env (or ~/.hermes/.env). Optional S3_PREFIX.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

PAYLOAD_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REMOTE_ENV="${REMOTE_ENV:-$PAYLOAD_DIR/remote.env}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
JOBS="$HERMES_HOME/cron/jobs.json"

# Fresh-install gate: an existing job set means this host is not waiting for a restore.
if [[ -f "$JOBS" ]]; then
  log "cron/jobs.json already present — nothing to restore"
  exit 0
fi

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

DEST="s3://${S3_BUCKET}/${S3_PREFIX}"

log "Checking ${DEST} for a restore"
aws s3api head-bucket --bucket "$S3_BUCKET" --region "$AWS_DEFAULT_REGION" \
  || die "cannot access s3://${S3_BUCKET} (bucket missing, wrong region, or IAM)"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/hermes-s3-restore.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

# --- cron jobs: install only when the mirror has them; local file stays if present ---
log "Downloading cron/jobs.json"
if aws s3 cp "${DEST}/cron/jobs.json" "$STAGE/jobs.json" --region "$AWS_DEFAULT_REGION" 2>/dev/null; then
  if [[ -f "$JOBS" ]]; then
    warn "cron/jobs.json appeared while restoring — keeping the local copy"
  else
    bash "$SCRIPT_DIR/install-cron-jobs.sh" "$STAGE/jobs.json" \
      || die "cron install failed (no Python with cron.jobs importable)"
    log "Installed cron jobs from S3 backup"
  fi
else
  warn "no cron/jobs.json in ${DEST} — cron stays empty"
fi

# --- custom skills: merge from the mirror; no pruning, local-only skills survive ---
log "Downloading custom skills"
mkdir -p "$STAGE/skills"
aws s3 sync "${DEST}/skills" "$STAGE/skills" --region "$AWS_DEFAULT_REGION" >/dev/null 2>&1 || true
if [[ -n "$(find "$STAGE/skills" -name SKILL.md -print -quit 2>/dev/null)" ]]; then
  STAGE_TAR="$STAGE/skills.tgz"
  tar -czf "$STAGE_TAR" -C "$STAGE/skills" .
  bash "$SCRIPT_DIR/unpack-custom-skills.sh" "$STAGE_TAR" >/dev/null
  log "Merged custom skills from S3 backup into $HERMES_HOME/skills"
else
  warn "no custom skills in ${DEST} — local skills unchanged"
fi

# --- align unpinned jobs with model.default (same rule as config push) ---
if [[ -f "$JOBS" && -f "$SCRIPT_DIR/pin-cron-models.sh" ]]; then
  bash "$SCRIPT_DIR/pin-cron-models.sh" || warn "cron model pin after restore failed"
fi

log "S3 restore complete (add-only; existing files were not deleted)"