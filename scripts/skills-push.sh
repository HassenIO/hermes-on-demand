#!/usr/bin/env bash
# Push local ./skills/ custom packages to VPS ~/.hermes/skills/
# Mac control plane only — never installs Hermes locally.
# Does not touch Hermes builtin skills. Prunes remote custom skills
# missing from ./skills/ so push mirrors pull.
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

SRC="${ROOT}/skills"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/hermes-skills-push.XXXXXX")"
REMOTE_TAR="/tmp/hermes-custom-skills-push-$$.tgz"
trap 'rm -rf "$STAGING"; ssh_cmd "rm -f \"$REMOTE_TAR\" /tmp/unpack-custom-skills.sh" 2>/dev/null || true' EXIT

[[ -d "$SRC" ]] || die "missing $SRC — run make skills-pull first or add packages there"

# Local skill packages (dirs containing SKILL.md)
mapfile -t LOCAL_SKILLS < <(find "$SRC" -name SKILL.md -type f | sed "s|^$SRC/||;s|/SKILL.md\$||" | sort)
if ((${#LOCAL_SKILLS[@]} == 0)); then
  die "no SKILL.md packages under $SRC"
fi

log "SSH probe ${TARGET_USER}@${TARGET_HOST}:${SSH_PORT}"
ssh_cmd "true"

log "Packing ${#LOCAL_SKILLS[@]} local skill(s)"
printf '%s\n' "${LOCAL_SKILLS[@]}" | sed 's/^/  /'

# Refuse packaging anything that looks like a path escape
for rel in "${LOCAL_SKILLS[@]}"; do
  case "$rel" in
    ''|.*|/*|*..*) die "unsafe skill path: $rel" ;;
  esac
done

tar -czf "$STAGING/skills.tgz" --exclude 'README.md' -C "$SRC" .
# Ensure archive has content
[[ -s "$STAGING/skills.tgz" ]] || die "failed to create skills archive"

scp_cmd "$STAGING/skills.tgz" "${TARGET_USER}@${TARGET_HOST}:${REMOTE_TAR}"
scp_cmd "$ROOT/scripts/remote/unpack-custom-skills.sh" \
  "${TARGET_USER}@${TARGET_HOST}:/tmp/unpack-custom-skills.sh"
ssh_cmd "chmod +x /tmp/unpack-custom-skills.sh"

log "Installing on VPS → ~/.hermes/skills (custom only, prune remote extras)"
RESULT="$(ssh_cmd "bash /tmp/unpack-custom-skills.sh '$REMOTE_TAR' --prune")"
printf '%s\n' "$RESULT" | sed 's/^/  /'

INSTALLED="$(printf '%s\n' "$RESULT" | grep -c '^installed ' || true)"
PRUNED="$(printf '%s\n' "$RESULT" | grep -c '^pruned ' || true)"
log "Pushed ${INSTALLED} skill(s), pruned ${PRUNED} remote-only custom package(s)"

if [[ -n "${S3_BUCKET:-}" ]]; then
  log "Refreshing S3 snapshot"
  if ! bash "$ROOT/scripts/deploy.sh" --s3-snapshot; then
    warn "S3 snapshot failed — skills are on the VPS; re-run ./scripts/deploy.sh --s3-snapshot"
  fi
fi
