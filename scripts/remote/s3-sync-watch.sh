#!/usr/bin/env bash
# Runs ON the VPS. Long-running: upload skills + cron to S3 after local changes.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
SKILLS="$HERMES_HOME/skills"
CRON="$HERMES_HOME/cron"
DEBOUNCE="${S3_SYNC_DEBOUNCE_SEC:-10}"
SNAPSHOT="$SCRIPT_DIR/s3-snapshot.sh"

mkdir -p "$SKILLS" "$CRON"

cleanup() {
  [[ -n "${inotify_pid:-}" ]] && kill "$inotify_pid" 2>/dev/null || true
}
trap cleanup EXIT

command -v inotifywait >/dev/null 2>&1 || die "inotifywait missing (install inotify-tools)"
[[ -x "$SNAPSHOT" ]] || die "missing $SNAPSHOT"

coproc INOTIFY {
  inotifywait -m -r -q \
    -e close_write,create,delete,move \
    --exclude '(jobs\.json\.bak|\.sha256$|/\.)' \
    --format '%w%f' \
    "$SKILLS" "$CRON"
}
inotify_pid=$INOTIFY_PID
exec 3<&"${INOTIFY[0]}"

log "Watching $SKILLS and $CRON/jobs.json (debounce ${DEBOUNCE}s)"

pending=1
quiet_since="$(date +%s)"

while kill -0 "$inotify_pid" 2>/dev/null; do
  path=""
  if IFS= read -r -t 1 path <&3; then
    case "$path" in
      "$CRON"/*)
        [[ "$path" == "$CRON/jobs.json" ]] || continue
        ;;
      "$SKILLS"/*) ;;
      *) continue ;;
    esac
    pending=1
    quiet_since="$(date +%s)"
    continue
  fi
  now="$(date +%s)"
  if [[ "$pending" -eq 1 && $((now - quiet_since)) -ge "$DEBOUNCE" ]]; then
    pending=0
    if bash "$SNAPSHOT"; then
      log "S3 snapshot refreshed"
    else
      warn "S3 snapshot failed — retrying after further changes"
      pending=1
      quiet_since="$(date +%s)"
    fi
  fi
done

warn "inotifywait exited"
exit 1
