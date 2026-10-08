#!/usr/bin/env bash
# Pull custom (non-builtin) skills from the VPS into ./skills/
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

DEST="${ROOT}/skills"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/hermes-skills-pull.XXXXXX")"
REMOTE_TAR="/tmp/hermes-custom-skills-$$.tgz"
trap 'rm -rf "$STAGING"; ssh_cmd "rm -f \"$REMOTE_TAR\"" 2>/dev/null || true' EXIT

log "SSH probe ${TARGET_USER}@${TARGET_HOST}:${SSH_PORT}"
ssh_cmd "true"

# Ship packer (no full deploy payload required)
scp_cmd "$ROOT/scripts/remote/pack-custom-skills.sh" \
  "${TARGET_USER}@${TARGET_HOST}:/tmp/pack-custom-skills.sh"
ssh_cmd "chmod +x /tmp/pack-custom-skills.sh"

log "Packing custom skills on VPS (exclude Hermes builtin tree)"
LIST="$(ssh_cmd "bash /tmp/pack-custom-skills.sh '$REMOTE_TAR'")"
ssh_cmd "rm -f /tmp/pack-custom-skills.sh"

if [[ -z "${LIST//[$'\t\r\n ']/}" ]]; then
  log "No custom skills on VPS — nothing to pull"
  mkdir -p "$DEST"
  exit 0
fi

log "Custom skills:"
printf '%s\n' "$LIST" | sed 's/^/  /'

scp_cmd "${TARGET_USER}@${TARGET_HOST}:${REMOTE_TAR}" "$STAGING/skills.tgz"

if [[ ! -s "$STAGING/skills.tgz" ]]; then
  die "remote tar empty despite skill list"
fi

EXTRACT="$STAGING/extract"
mkdir -p "$EXTRACT"
tar -xzf "$STAGING/skills.tgz" -C "$EXTRACT"

mkdir -p "$DEST"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$EXTRACT/" "$DEST/"
else
  # Portable fallback: replace tree contents
  find "$DEST" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  cp -R "$EXTRACT"/. "$DEST/"
fi

COUNT="$(find "$DEST" -name SKILL.md | wc -l | tr -d ' ')"
log "Pulled $COUNT custom skill(s) → $DEST"
find "$DEST" -name SKILL.md | sed "s|^$DEST/||;s|/SKILL.md\$||" | sort | sed 's/^/  /'
