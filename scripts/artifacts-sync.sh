#!/usr/bin/env bash
# Git-style sync of ./artifacts with the live Hermes files on the VPS.
# Local control plane only. Pushes through deploy.sh --artifacts when needed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=lib/runtime-env.sh
source "$ROOT/scripts/lib/runtime-env.sh"
# shellcheck source=lib/artifacts-sync.sh
source "$ROOT/scripts/lib/artifacts-sync.sh"

load_dotenv "$ROOT/.env"
require_vars TARGET_HOST TARGET_USER
refuse_local_target

SSH_PORT="${SSH_PORT:-22}"
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -p "$SSH_PORT")
if [[ -n "${SSH_IDENTITY_FILE:-}" ]]; then
  SSH_OPTS+=(-i "$SSH_IDENTITY_FILE")
fi

ssh_cmd() {
  ssh "${SSH_OPTS[@]}" "${TARGET_USER}@${TARGET_HOST}" "$@"
}

# Copies a remote file to $2. $1 is a remote shell path expression. Returns 3 when missing.
remote_fetch() {
  local rc=0
  ssh_cmd "f=\"$1\"; [ -f \"\$f\" ] || exit 3; cat \"\$f\"" >"$2" || rc=$?
  if ((rc == 3)); then
    rm -f "$2"
    return 3
  fi
  ((rc == 0)) || die "failed to read $1 on VPS"
}

LOCAL_DIR="$ROOT/artifacts"
BASE_DIR="$ROOT/.hermes-setup/artifacts"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/hermes-artifacts-sync.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

log "SSH probe ${TARGET_USER}@${TARGET_HOST}:${SSH_PORT}"
ssh_cmd "true"

mkdir -p "$LOCAL_DIR" "$STAGING/remote"

log "Fetching live artifacts from VPS"
for f in "${ARTIFACT_FILES[@]}"; do
  remote_fetch "\${HERMES_HOME:-\$HOME/.hermes}/$(artifact_remote_path "$f")" "$STAGING/remote/$f" || true
done

if [[ ! -d "$BASE_DIR" ]]; then
  REMOTE_DIR_RAW="${REMOTE_DIR:-~/hermes-setup}"
  [[ "$REMOTE_DIR_RAW" == "~/"* ]] && REMOTE_DIR_RAW="\$HOME/${REMOTE_DIR_RAW:2}"
  log "No local sync base yet. Seeding it from the last push on the VPS"
  mkdir -p "$BASE_DIR"
  for f in "${ARTIFACT_FILES[@]}"; do
    remote_fetch "$REMOTE_DIR_RAW/artifacts/$f" "$BASE_DIR/$f" || true
  done
fi

CONFLICTS=()
for f in "${ARTIFACT_FILES[@]}"; do
  status="$(artifact_sync_one "$BASE_DIR/$f" "$LOCAL_DIR/$f" "$STAGING/remote/$f")"
  log "  $f: $status"
  [[ "$status" == "conflict" ]] && CONFLICTS+=("$f")
  if [[ -f "$STAGING/remote/$f" ]]; then
    artifact_normalize "$STAGING/remote/$f" >"$BASE_DIR/$f"
  else
    rm -f "$BASE_DIR/$f"
  fi
done

if ((${#CONFLICTS[@]})); then
  die "merge conflicts in: ${CONFLICTS[*]}. Fix the markers in artifacts/, then run make sync again. Nothing was pushed."
fi

PUSH=()
for f in "${ARTIFACT_FILES[@]}"; do
  if artifact_needs_push "$LOCAL_DIR/$f" "$STAGING/remote/$f"; then
    artifact_has_conflict_markers "$LOCAL_DIR/$f" \
      && die "artifacts/$f still has conflict markers. Nothing was pushed."
    PUSH+=("$f")
  fi
done

if ((${#PUSH[@]} == 0)); then
  log "Artifacts in sync. Nothing to push."
  exit 0
fi

log "Pushing local changes: ${PUSH[*]}"
bash "$ROOT/scripts/deploy.sh" --artifacts
for f in "${ARTIFACT_FILES[@]}"; do
  if [[ -f "$LOCAL_DIR/$f" ]]; then
    artifact_normalize "$LOCAL_DIR/$f" >"$BASE_DIR/$f"
  fi
done
log "Sync done. Start a new Telegram chat (/new) so the profile reloads."
