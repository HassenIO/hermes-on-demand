#!/usr/bin/env bash
# Push local ./cron/jobs.json to VPS ~/.hermes/cron/jobs.json
# Local control plane only — never installs Hermes locally.
# Replaces remote job set (local is source of truth after cron-pull + edit).
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

SRC="${ROOT}/cron/jobs.json"
REMOTE_TMP="/tmp/hermes-cron-jobs-push-$$.json"
trap 'ssh_cmd "rm -f \"$REMOTE_TMP\" /tmp/install-cron-jobs.sh" 2>/dev/null || true' EXIT

[[ -f "$SRC" ]] || die "missing $SRC — run make cron-pull first or add jobs there"

# Local validate before network
python3 "$ROOT/scripts/lib/cron_validate.py" "$SRC"

log "SSH probe ${TARGET_USER}@${TARGET_HOST}:${SSH_PORT}"
ssh_cmd "true"

log "Uploading cron/jobs.json"
scp_cmd "$SRC" "${TARGET_USER}@${TARGET_HOST}:${REMOTE_TMP}"
scp_cmd "$ROOT/scripts/remote/install-cron-jobs.sh" \
  "${TARGET_USER}@${TARGET_HOST}:/tmp/install-cron-jobs.sh"
ssh_cmd "chmod +x /tmp/install-cron-jobs.sh"

log "Installing on VPS via Hermes save_jobs (replace=True)"
RESULT="$(ssh_cmd "bash /tmp/install-cron-jobs.sh '$REMOTE_TMP'")"
printf '%s\n' "$RESULT" | sed 's/^/  /'

log "Done — gateway re-reads jobs.json each tick (no restart required)"

if [[ -n "${S3_BUCKET:-}" ]]; then
  log "Refreshing S3 snapshot"
  if ! bash "$ROOT/scripts/deploy.sh" --s3-snapshot; then
    warn "S3 snapshot failed — cron is on the VPS; re-run ./scripts/deploy.sh --s3-snapshot"
  fi
fi
