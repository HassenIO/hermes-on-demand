#!/usr/bin/env bash
# Runs ON the VPS. Install Agent-Reach as Hermes skill + custom Docker terminal image.
# Zero-config channels only (web/YouTube/GitHub/RSS/Exa/Bilibili).
#
# Upstream: https://github.com/Panniantong/Agent-Reach
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
AGENT_REACH_HOME="${AGENT_REACH_HOME:-$HOME/.agent-reach}"
IMAGE_NAME="${AGENT_REACH_IMAGE:-hermes-terminal:agent-reach}"
AGENT_REACH_REF="${AGENT_REACH_REF:-main}"

ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EXT_DIR="$ROOT/extensions/agent-reach"
if [[ ! -d "$EXT_DIR/docker" ]]; then
  for cand in "$HOME/hermes-setup/extensions/agent-reach"; do
    [[ -d "$cand/docker" ]] && EXT_DIR="$cand" && break
  done
fi
[[ -d "$EXT_DIR/docker" ]] || die "extensions/agent-reach not found (sync repo first)"

command -v docker >/dev/null 2>&1 || die "docker required"
command -v hermes >/dev/null 2>&1 || die "hermes not on PATH"

log "Agent-Reach install (image=$IMAGE_NAME ref=$AGENT_REACH_REF)"

mkdir -p "$AGENT_REACH_HOME" "$HERMES_HOME/cache/documents" "$HERMES_HOME/memories"
chmod 700 "$AGENT_REACH_HOME"

# --- Build terminal image (tools live here for Docker backend) ---
log "Building Docker image $IMAGE_NAME (may take several minutes)"
docker build \
  --build-arg "AGENT_REACH_REF=$AGENT_REACH_REF" \
  -t "$IMAGE_NAME" \
  -f "$EXT_DIR/docker/Dockerfile" \
  "$EXT_DIR/docker"

log "Verifying tools in image"
docker run --rm "$IMAGE_NAME" bash -lc '
  set -e
  yt-dlp --version
  gh --version
  python3 -c "import feedparser; print(\"feedparser ok\")"
  command -v agent-reach
  command -v curl
' || die "image tool smoke failed"

# --- Hermes skill ---
SKILL_DST="$HERMES_HOME/skills/agent-reach"
log "Installing skill → $SKILL_DST"
mkdir -p "$SKILL_DST"
install -m 644 "$EXT_DIR/skill/SKILL.md" "$SKILL_DST/SKILL.md"

# --- Patch only terminal keys in config.yaml (preserve model/memory/web/display) ---
log "Patching terminal.docker_image + volumes (non-destructive)"
CFG="$HERMES_HOME/config.yaml"
MOUNT="${AGENT_REACH_HOME}:/root/.agent-reach"
OUT_MOUNT="${HERMES_HOME}/cache/documents:/output"
MEM_MOUNT="${HERMES_HOME}/memories:${HERMES_HOME}/memories:ro"

if [[ ! -f "$CFG" ]]; then
  die "missing $CFG — run bootstrap/config deploy first"
fi

# Prefer hermes CLI for simple keys when available
hermes config set terminal.backend docker >/dev/null 2>&1 || true
hermes config set terminal.docker_image "$IMAGE_NAME" >/dev/null 2>&1 || true

python3 - "$CFG" "$IMAGE_NAME" "$MOUNT" "$OUT_MOUNT" "$MEM_MOUNT" <<'PY'
from pathlib import Path
import re, sys

cfg_path, image, mount, out_m, mem_m = sys.argv[1:6]
path = Path(cfg_path)
text = path.read_text()

# Never touch non-terminal top-level sections.
if not re.search(r"(?m)^terminal:\s*$", text):
    text = text.rstrip() + "\n\nterminal:\n  backend: docker\n"

# docker_image under terminal only: replace first occurrence after terminal:
def sub_in_terminal(src: str, key: str, value_line: str) -> str:
    """Replace or insert a 2-space key under the terminal: block only."""
    m = re.search(r"(?ms)^(terminal:\n)(.*?)(?=^[a-zA-Z_]|\Z)", src)
    if not m:
        return src
    head, body, end = m.group(1), m.group(2), src[m.end() :]
    # body ends before next top-level key; m.end() is start of next key
    # Actually end capture is wrong — re-do with span
    return src  # fallback unused

m = re.search(r"(?ms)^terminal:\n(.*?)(?=^[a-zA-Z_]|\Z)", text)
if not m:
    sys.exit("no terminal block")
start, stop = m.start(), m.end()
block = text[start:stop]
rest_after = text[stop:]
before = text[:start]

# backend
if re.search(r"(?m)^\s+backend:\s*", block):
    block = re.sub(r"(?m)^(\s+backend:\s*).*$", r"\1docker", block, count=1)
else:
    block = block.rstrip() + "\n  backend: docker\n"

# docker_image
if re.search(r"(?m)^\s+docker_image:\s*", block):
    block = re.sub(r"(?m)^(\s+docker_image:\s*).*$", rf'\1"{image}"', block, count=1)
else:
    block = block.rstrip() + f'\n  docker_image: "{image}"\n'

# docker_volumes: merge wanted mounts
wanted = [out_m, mem_m, mount]
existing = re.findall(r'(?m)^\s+-\s*"?([^"\n]+)"?\s*$', 
                      (re.search(r"(?ms)^\s+docker_volumes:\n((?:\s+-\s*.*\n)*)", block) or type("X",(object,),{"group":lambda s,i:""})()).group(1) if re.search(r"(?ms)^\s+docker_volumes:\n", block) else "")
vols = []
seen = set()
for v in existing + wanted:
    v = v.strip().strip('"').strip("'")
    if v and v not in seen:
        seen.add(v)
        vols.append(v)
vol_yaml = "  docker_volumes:\n" + "".join(f'    - "{v}"\n' for v in vols)
if re.search(r"(?ms)^\s+docker_volumes:\n(?:\s+-\s*.*\n)*", block):
    block = re.sub(r"(?ms)^\s+docker_volumes:\n(?:\s+-\s*.*\n)*", vol_yaml, block, count=1)
else:
    block = block.rstrip() + "\n" + vol_yaml

# docker_forward_env GITHUB_TOKEN
if re.search(r"(?m)^\s+docker_forward_env:\s*$", block):
    if "GITHUB_TOKEN" not in block:
        block = re.sub(
            r"(?m)^(\s+docker_forward_env:\s*)$",
            r"\1\n    - GITHUB_TOKEN",
            block,
            count=1,
        )
elif "docker_forward_env:" not in block:
    block = block.rstrip() + "\n  docker_forward_env:\n    - GITHUB_TOKEN\n"

if not block.endswith("\n"):
    block += "\n"

path.write_text(before + block + rest_after)
print(f"patched terminal block in {cfg_path}")
print(f"docker_image={image}")
for v in vols:
    print(f"  volume {v}")
PY

# Drop old Hermes containers so next tool call uses the new image
log "Removing old Hermes Docker sandboxes (pick up new image)"
ids="$(docker ps -aq --filter label=hermes-agent=1 2>/dev/null || true)"
if [[ -n "${ids//[$'\n\r\t ']/}" ]]; then
  # shellcheck disable=SC2086
  docker rm -f $ids >/dev/null 2>&1 || true
fi

# Host-side thin CLI for doctor (optional — tools already live in the image)
HOST_VENV="${AGENT_REACH_HOST_VENV:-$HERMES_HOME/.agent-reach/venv}"
if [[ "${AGENT_REACH_HOST_CLI:-1}" == "1" ]]; then
  log "Host doctor CLI → $HOST_VENV (best-effort)"
  if [[ ! -x "$HOST_VENV/bin/python" ]]; then
    if ! python3 -m venv "$HOST_VENV" 2>/dev/null; then
      if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq >/dev/null 2>&1 || true
        apt-get install -y -qq python3-venv python3-pip >/dev/null 2>&1 || true
      fi
      rm -rf "$HOST_VENV"
      python3 -m venv "$HOST_VENV" 2>/dev/null || true
    fi
  fi
  if [[ -x "$HOST_VENV/bin/python" ]]; then
    "$HOST_VENV/bin/python" -m ensurepip --upgrade >/dev/null 2>&1 || true
    "$HOST_VENV/bin/python" -m pip install -q --upgrade pip \
      && "$HOST_VENV/bin/python" -m pip install -q \
           "https://github.com/Panniantong/agent-reach/archive/${AGENT_REACH_REF}.zip" \
      || warn "host agent-reach pip install failed (image still OK)"
    mkdir -p "${HOME}/.local/bin"
    if [[ -x "$HOST_VENV/bin/agent-reach" ]]; then
      ln -sfn "$HOST_VENV/bin/agent-reach" "${HOME}/.local/bin/agent-reach"
    fi
  else
    warn "host venv unavailable — doctor via: docker run --rm $IMAGE_NAME agent-reach doctor"
  fi
fi

log "Restarting gateway"
hermes gateway restart 2>/dev/null || hermes gateway start 2>/dev/null || true
sleep 4
hermes gateway status 2>/dev/null || true

log "Agent-Reach ready"
log "  image:  $IMAGE_NAME"
log "  skill:  $SKILL_DST/SKILL.md"
log "  config: $AGENT_REACH_HOME"
log "In Telegram: /new then ask about a YouTube URL or GitHub repo."
