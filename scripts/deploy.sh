#!/usr/bin/env bash
# Local control-plane entrypoint. Never installs Hermes on this machine.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=lib/runtime-env.sh
source "$ROOT/scripts/lib/runtime-env.sh"

MODE="full" # full | config-only | health | firecrawl | artifacts | update | mnemosyne | agent-reach | notion | s3-snapshot
for arg in "$@"; do
  case "$arg" in
    --config-only) MODE="config-only" ;;
    --health) MODE="health" ;;
    --firecrawl) MODE="firecrawl" ;;
    --artifacts) MODE="artifacts" ;;
    --update) MODE="update" ;;
    --mnemosyne) MODE="mnemosyne" ;;
    --agent-reach) MODE="agent-reach" ;;
    --notion) MODE="notion" ;;
    --s3-snapshot) MODE="s3-snapshot" ;;
    -h|--help)
      cat <<'EOF'
Usage: ./scripts/deploy.sh [--config-only|--health|--firecrawl|--artifacts|--update|--mnemosyne|--agent-reach|--notion|--s3-snapshot]

  (default)      Full remote bootstrap (Hermes + Firecrawl + Mnemosyne + Agent-Reach + artifacts)
  --config-only  Push secrets + config.yaml + artifacts, re-apply Docker patch, restart
  --artifacts    Push profile seeds; also syncs payload, applies timezone, restarts gateway
  --health       Remote healthcheck (re-applies Docker patch if missing)
  --firecrawl    Deploy/start self-hosted Firecrawl only
  --mnemosyne    Install/refresh Mnemosyne side-venv + Hermes wrapper plugin
  --agent-reach  Build terminal image + install Agent-Reach skill (zero-config web CLIs)
  --notion       Notion REST CLI + skill (install skipped unless BOTH NOTION_* are set; payload sync and timezone still run)
  --update       hermes update + Docker patch + Mnemosyne + Agent-Reach + Notion refresh
  --s3-snapshot  Mirror custom skills + cron/jobs.json to S3 (no gateway restart)
EOF
      exit 0
      ;;
    *) die "unknown arg: $arg" ;;
  esac
done

ENV_FILE="$ROOT/.env"
load_dotenv "$ENV_FILE"

require_vars TARGET_HOST TARGET_USER OPENROUTER_API_KEY TELEGRAM_BOT_TOKEN TELEGRAM_ALLOWED_USERS

# Safety: do not install Hermes on the control machine by accident
refuse_local_target

SSH_PORT="${SSH_PORT:-22}"
REMOTE_DIR_RAW="${REMOTE_DIR:-~/hermes-setup}"
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -p "$SSH_PORT")
if [[ -n "${SSH_IDENTITY_FILE:-}" ]]; then
  SSH_OPTS+=(-i "$SSH_IDENTITY_FILE")
fi

ssh_cmd() {
  ssh "${SSH_OPTS[@]}" "${TARGET_USER}@${TARGET_HOST}" "$@"
}

scp_cmd() {
  scp -P "$SSH_PORT" ${SSH_IDENTITY_FILE:+-i "$SSH_IDENTITY_FILE"} "$@"
}

log "SSH probe ${TARGET_USER}@${TARGET_HOST}:${SSH_PORT}"
ssh_cmd "true"

# Resolve remote dir on the server (expand ~ as remote user)
REMOTE_DIR="$(ssh_cmd "python3 - <<'PY'
import os
print(os.path.expanduser('${REMOTE_DIR_RAW}'))
PY
")"
log "Remote payload dir: $REMOTE_DIR"

# Build filtered runtime env (no deploy keys)
RUNTIME_ENV="$(mktemp)"
trap 'rm -f "$RUNTIME_ENV"' EXIT
build_runtime_env >"$RUNTIME_ENV"
chmod 600 "$RUNTIME_ENV"

if [[ "$MODE" == "health" ]]; then
  log "Remote healthcheck only"
  ssh_cmd "bash '$REMOTE_DIR/scripts/remote/healthcheck.sh'"
  exit 0
fi

log "Syncing payload to VPS"
ssh_cmd "mkdir -p '$REMOTE_DIR/scripts/lib' '$REMOTE_DIR/scripts/remote' '$REMOTE_DIR/config' '$REMOTE_DIR/firecrawl' '$REMOTE_DIR/artifacts' '$REMOTE_DIR/extensions'"

# Prefer rsync if available both sides
if command -v rsync >/dev/null 2>&1 && ssh_cmd "command -v rsync >/dev/null 2>&1"; then
  RSYNC_SSH="ssh -p $SSH_PORT -o BatchMode=yes -o StrictHostKeyChecking=accept-new"
  [[ -n "${SSH_IDENTITY_FILE:-}" ]] && RSYNC_SSH+=" -i $SSH_IDENTITY_FILE"
  rsync -az -e "$RSYNC_SSH" \
    "$ROOT/scripts/lib/" "${TARGET_USER}@${TARGET_HOST}:${REMOTE_DIR}/scripts/lib/"
  rsync -az -e "$RSYNC_SSH" \
    "$ROOT/scripts/remote/" "${TARGET_USER}@${TARGET_HOST}:${REMOTE_DIR}/scripts/remote/"
  rsync -az -e "$RSYNC_SSH" \
    "$ROOT/config/" "${TARGET_USER}@${TARGET_HOST}:${REMOTE_DIR}/config/"
  rsync -az -e "$RSYNC_SSH" \
    --exclude '.env' \
    "$ROOT/firecrawl/" "${TARGET_USER}@${TARGET_HOST}:${REMOTE_DIR}/firecrawl/"
  if [[ -d "$ROOT/artifacts" ]]; then
    rsync -az -e "$RSYNC_SSH" \
      --exclude 'README.md' \
      "$ROOT/artifacts/" "${TARGET_USER}@${TARGET_HOST}:${REMOTE_DIR}/artifacts/"
  fi
  if [[ -d "$ROOT/extensions" ]]; then
    rsync -az -e "$RSYNC_SSH" \
      "$ROOT/extensions/" "${TARGET_USER}@${TARGET_HOST}:${REMOTE_DIR}/extensions/"
  fi
else
  scp_cmd -r "$ROOT/scripts/lib/"* "${TARGET_USER}@${TARGET_HOST}:${REMOTE_DIR}/scripts/lib/"
  scp_cmd -r "$ROOT/scripts/remote/"* "${TARGET_USER}@${TARGET_HOST}:${REMOTE_DIR}/scripts/remote/"
  scp_cmd -r "$ROOT/config/"* "${TARGET_USER}@${TARGET_HOST}:${REMOTE_DIR}/config/"
  scp_cmd "$ROOT/firecrawl/docker-compose.yml" "$ROOT/firecrawl/.env.example" \
    "${TARGET_USER}@${TARGET_HOST}:${REMOTE_DIR}/firecrawl/"
  ssh_cmd "mkdir -p '$REMOTE_DIR/firecrawl/lite'"
  scp_cmd "$ROOT/firecrawl/lite/"* \
    "${TARGET_USER}@${TARGET_HOST}:${REMOTE_DIR}/firecrawl/lite/"
  if [[ -d "$ROOT/artifacts" ]]; then
    for f in SOUL.md USER.md MEMORY.md CV.md; do
      [[ -f "$ROOT/artifacts/$f" ]] || continue
      scp_cmd "$ROOT/artifacts/$f" \
        "${TARGET_USER}@${TARGET_HOST}:${REMOTE_DIR}/artifacts/"
    done
  fi
  if [[ -d "$ROOT/extensions" ]]; then
    ssh_cmd "mkdir -p '$REMOTE_DIR/extensions'"
    scp_cmd -r "$ROOT/extensions/"* \
      "${TARGET_USER}@${TARGET_HOST}:${REMOTE_DIR}/extensions/" 2>/dev/null || true
  fi
fi

scp_cmd "$RUNTIME_ENV" "${TARGET_USER}@${TARGET_HOST}:${REMOTE_DIR}/remote.env"
ssh_cmd "chmod 600 '$REMOTE_DIR/remote.env' && chmod +x '$REMOTE_DIR/scripts/remote/'*.sh 2>/dev/null || true"

# Apply VPS timezone on every deploy mode (except health-only above)
log "Applying VPS timezone (TIMEZONE=${TIMEZONE:-Asia/Dubai})"
ssh_cmd "TIMEZONE='${TIMEZONE:-Asia/Dubai}' bash '$REMOTE_DIR/scripts/remote/set-timezone.sh'" \
  || warn "timezone apply failed — check TIMEZONE= in .env"

if [[ "$MODE" == "s3-snapshot" ]]; then
  log "Uploading skills + cron snapshot to S3"
  ssh_cmd "bash '$REMOTE_DIR/scripts/remote/s3-snapshot.sh'"
  log "Starting S3 file watcher"
  ssh_cmd "bash '$REMOTE_DIR/scripts/remote/s3-sync-install.sh'"
  log "S3 snapshot done. Further skills/cron edits on the VPS sync on their own."
  exit 0
fi

if [[ "$MODE" == "firecrawl" ]]; then
  log "Deploying self-hosted Firecrawl + wiring Hermes (mode=${FIRECRAWL_MODE:-lite})"
  ssh_cmd "FIRECRAWL_MODE='${FIRECRAWL_MODE:-lite}' bash '$REMOTE_DIR/scripts/remote/firecrawl-up.sh'"
  log "Firecrawl deploy done. Ask the bot to scrape a URL."
  exit 0
fi

if [[ "$MODE" == "mnemosyne" ]]; then
  log "Installing/refreshing Mnemosyne (side-venv + wrapper)"
  ssh_cmd "MNEMOSYNE_PROFILE='${MNEMOSYNE_PROFILE:-embeddings}' bash '$REMOTE_DIR/scripts/remote/mnemosyne-up.sh'"
  log "Mnemosyne done. /new in Telegram, then hermes memory status."
  exit 0
fi

if [[ "$MODE" == "agent-reach" ]]; then
  log "Installing Agent-Reach (custom terminal image + Hermes skill)"
  ssh_cmd "AGENT_REACH_REF='${AGENT_REACH_REF:-main}' bash '$REMOTE_DIR/scripts/remote/agent-reach-up.sh'"
  log "Agent-Reach done. /new in Telegram, then try a YouTube or GitHub URL."
  exit 0
fi

if [[ "$MODE" == "notion" ]]; then
  if [[ -z "${NOTION_API_KEY:-}" || -z "${NOTION_REPORTS_PARENT_PAGE_ID:-}" ]]; then
    log "Skipping Notion — both required in local .env (neither alone is enough):"
    log "  NOTION_API_KEY=ntn_..."
    log "  NOTION_REPORTS_PARENT_PAGE_ID=<parent-page-uuid>"
    log "Docs: docs/tools/notion.md — Notion install skipped. Payload sync and timezone already ran."
    exit 0
  fi
  log "Installing Notion REST CLI + notion-reports skill"
  ssh_cmd "REMOTE_ENV='$REMOTE_DIR/remote.env' bash '$REMOTE_DIR/scripts/remote/notion-up.sh'"
  log "Notion done. /new in Telegram, then ask to post a test report."
  exit 0
fi

if [[ "$MODE" == "artifacts" ]]; then
  log "Installing artifacts (SOUL.md + USER.md) on VPS"
  ssh_cmd "bash '$REMOTE_DIR/scripts/remote/install-artifacts.sh'"
  ssh_cmd "export PATH=\"\$HOME/.local/bin:/usr/local/bin:\$PATH\"; hermes gateway restart 2>/dev/null || hermes gateway start 2>/dev/null || true"
  log "Artifacts applied. Start a new Telegram chat (/new) so the profile reloads."
  exit 0
fi

if [[ "$MODE" == "update" ]]; then
  log "Remote Hermes update + repair (Docker patch, links, gateway)"
  ssh_cmd "bash '$REMOTE_DIR/scripts/remote/hermes-update.sh'"
  ssh_cmd "bash '$REMOTE_DIR/scripts/remote/healthcheck.sh'"
  log "Update complete."
  exit 0
fi

if [[ "$MODE" == "config-only" ]]; then
  log "Config-only: write Hermes home + artifacts + restart gateway"
  ssh_cmd "bash -s" <<EOF
set -euo pipefail
export PATH="\$HOME/.local/bin:/usr/local/bin:\$PATH"
HERMES_HOME="\${HERMES_HOME:-\$HOME/.hermes}"
mkdir -p "\$HERMES_HOME"
install -m 600 '$REMOTE_DIR/remote.env' "\$HERMES_HOME/.env"
install -m 644 '$REMOTE_DIR/config/config.yaml.example' "\$HERMES_HOME/config.yaml"
bash '$REMOTE_DIR/scripts/remote/install-artifacts.sh'
bash '$REMOTE_DIR/scripts/remote/patch-hermes-docker.sh' 2>/dev/null || true
# keep hermes CLI symlink healthy (doctor --fix can create a loop)
if [[ -L "\$HOME/.local/bin/hermes" ]] || [[ ! -e "\$HOME/.local/bin/hermes" ]]; then
  mkdir -p "\$HOME/.local/bin"
  ln -sfn /usr/local/lib/hermes-agent/venv/bin/hermes "\$HOME/.local/bin/hermes" 2>/dev/null || true
fi
hermes gateway restart 2>/dev/null || hermes gateway start
hermes gateway status || true
# Pin cron jobs to model.default (skip a different explicit model; avoid drift_skip)
bash '$REMOTE_DIR/scripts/remote/pin-cron-models.sh' || true
EOF
  # Re-apply Notion if both keys present (config.yaml.example has no mcp/notion blocks)
  if [[ -n "${NOTION_API_KEY:-}" && -n "${NOTION_REPORTS_PARENT_PAGE_ID:-}" ]]; then
    log "Re-applying Notion after config push"
    ssh_cmd "bash '$REMOTE_DIR/scripts/remote/notion-up.sh'" || warn "Notion re-apply failed"
    # notion-up may rewrite config.yaml — re-pin cron models
    ssh_cmd "bash '$REMOTE_DIR/scripts/remote/pin-cron-models.sh'" || warn "cron pin after notion failed"
  fi
  ssh_cmd "bash '$REMOTE_DIR/scripts/remote/healthcheck.sh'"
  log "Config deploy done. Message Telegram and/or Discord (/new to reload profile)."
  exit 0
fi

log "Full remote bootstrap (this may take several minutes)"
ssh_cmd "bash '$REMOTE_DIR/scripts/remote/bootstrap.sh'"

# Default stack includes Firecrawl lite (small VPS). Opt out: SKIP_FIRECRAWL=1
if [[ "${SKIP_FIRECRAWL:-}" != "1" ]]; then
  log "Starting Firecrawl lite (SKIP_FIRECRAWL=1 to skip)"
  ssh_cmd "FIRECRAWL_MODE='${FIRECRAWL_MODE:-lite}' bash '$REMOTE_DIR/scripts/remote/firecrawl-up.sh'" \
    || warn "Firecrawl setup failed — Hermes gateway may still work; re-run ./scripts/deploy.sh --firecrawl"
else
  log "Skipping Firecrawl (SKIP_FIRECRAWL=1)"
fi

# Default stack includes Mnemosyne (side-venv survives hermes update). Opt out: SKIP_MNEMOSYNE=1
if [[ "${SKIP_MNEMOSYNE:-}" != "1" ]]; then
  log "Installing Mnemosyne memory provider (SKIP_MNEMOSYNE=1 to skip)"
  ssh_cmd "MNEMOSYNE_PROFILE='${MNEMOSYNE_PROFILE:-embeddings}' bash '$REMOTE_DIR/scripts/remote/mnemosyne-up.sh'" \
    || warn "Mnemosyne setup failed — re-run ./scripts/deploy.sh --mnemosyne"
else
  log "Skipping Mnemosyne (SKIP_MNEMOSYNE=1)"
fi

# Default stack includes Agent-Reach (custom Docker terminal image + skill). Opt out: SKIP_AGENT_REACH=1
if [[ "${SKIP_AGENT_REACH:-}" != "1" ]]; then
  log "Installing Agent-Reach (SKIP_AGENT_REACH=1 to skip)"
  ssh_cmd "AGENT_REACH_REF='${AGENT_REACH_REF:-main}' bash '$REMOTE_DIR/scripts/remote/agent-reach-up.sh'" \
    || warn "Agent-Reach setup failed — re-run ./scripts/deploy.sh --agent-reach"
else
  log "Skipping Agent-Reach (SKIP_AGENT_REACH=1)"
fi

# Notion only when both env vars are set (omit either → skip)
if [[ -n "${NOTION_API_KEY:-}" && -n "${NOTION_REPORTS_PARENT_PAGE_ID:-}" ]]; then
  log "Installing Notion (both NOTION_API_KEY and NOTION_REPORTS_PARENT_PAGE_ID set)"
  ssh_cmd "bash '$REMOTE_DIR/scripts/remote/notion-up.sh'" \
    || warn "Notion setup failed — re-run ./scripts/deploy.sh --notion"
else
  log "Skipping Notion (set both NOTION_API_KEY and NOTION_REPORTS_PARENT_PAGE_ID to enable)"
fi

ssh_cmd "bash '$REMOTE_DIR/scripts/remote/healthcheck.sh'"

if [[ -n "${S3_BUCKET:-}" && -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" && -n "${AWS_DEFAULT_REGION:-}" ]]; then
  log "Uploading S3 snapshot and starting file watcher"
  if ssh_cmd "bash '$REMOTE_DIR/scripts/remote/s3-snapshot.sh'"; then
    ssh_cmd "bash '$REMOTE_DIR/scripts/remote/s3-sync-install.sh'" \
      || warn "S3 watcher failed to start — re-run ./scripts/deploy.sh --s3-snapshot"
  else
    warn "S3 snapshot failed — re-run ./scripts/deploy.sh --s3-snapshot"
  fi
elif [[ -n "${S3_BUCKET:-}" ]]; then
  warn "S3_BUCKET is set but AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, or AWS_DEFAULT_REGION is missing — snapshot skipped"
fi

log "Deploy complete. Open Telegram, optionally /sethome, then /new and message your bot."
