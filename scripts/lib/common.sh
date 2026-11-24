#!/usr/bin/env bash
# Shared helpers for local deploy and remote bootstrap.

set -euo pipefail

log()  { printf '==> %s\n' "$*"; }
warn() { printf '!!  %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Load KEY=VAL from a dotenv file into the current shell.
# Supports optional double/single quotes; ignores blank lines and comments.
load_dotenv() {
  local __dotenv_file="${1:?dotenv path required}"
  [[ -f "$__dotenv_file" ]] || die "missing env file: $__dotenv_file"
  # Prefixed locals: a dotenv key named like a local would overwrite it.
  local __dotenv_line __dotenv_key __dotenv_val
  while IFS= read -r __dotenv_line || [[ -n "$__dotenv_line" ]]; do
    __dotenv_line="${__dotenv_line#"${__dotenv_line%%[![:space:]]*}"}"
    __dotenv_line="${__dotenv_line%"${__dotenv_line##*[![:space:]]}"}"
    [[ -z "$__dotenv_line" || "$__dotenv_line" == \#* ]] && continue
    [[ "$__dotenv_line" == export\ * ]] && __dotenv_line="${__dotenv_line#export }"
    [[ "$__dotenv_line" == *=* ]] || continue
    __dotenv_key="${__dotenv_line%%=*}"
    __dotenv_val="${__dotenv_line#*=}"
    __dotenv_key="${__dotenv_key%"${__dotenv_key##*[![:space:]]}"}"
    __dotenv_key="${__dotenv_key#"${__dotenv_key%%[![:space:]]*}"}"
    __dotenv_val="${__dotenv_val#"${__dotenv_val%%[![:space:]]*}"}"
    __dotenv_val="${__dotenv_val%"${__dotenv_val##*[![:space:]]}"}"
    if [[ "$__dotenv_val" == \"*\" && "$__dotenv_val" == *\" ]]; then
      __dotenv_val="${__dotenv_val:1:${#__dotenv_val}-2}"
    elif [[ "$__dotenv_val" == \'*\' && "$__dotenv_val" == *\' ]]; then
      __dotenv_val="${__dotenv_val:1:${#__dotenv_val}-2}"
    fi
    printf -v "$__dotenv_key" '%s' "$__dotenv_val"
    export "$__dotenv_key"
  done < "$__dotenv_file"
}

require_vars() {
  local missing=()
  local v
  for v in "$@"; do
    [[ -n "${!v:-}" ]] || missing+=("$v")
  done
  if ((${#missing[@]})); then
    die "missing required env: ${missing[*]}"
  fi
}

# Expand leading ~ in a path (remote-safe when run locally for display).
expand_tilde() {
  local p="$1"
  if [[ "$p" == "~" ]]; then
    printf '%s\n' "$HOME"
  elif [[ "$p" == "~/"* ]]; then
    printf '%s\n' "$HOME/${p:2}"
  else
    printf '%s\n' "$p"
  fi
}

# True when container hermes is running. Inspect failure means it is not.
hermes_container_running() {
  local running
  running="$(docker inspect -f '{{.State.Running}}' hermes 2>/dev/null)" || return 1
  [[ "$running" == "true" ]]
}

# Stopped still counts: restart unless-stopped would bring it back beside the unit.
hermes_container_present() {
  docker inspect hermes >/dev/null 2>&1
}

# Host gateway start. Refuses while container hermes exists (one writer).
start_host_gateway() {
  if hermes_container_running; then
    die "refusing to start host gateway while container hermes is running"
  fi
  if hermes_container_present; then
    die "refusing to start host gateway while container hermes exists"
  fi
  hermes gateway restart 2>/dev/null || hermes gateway start
}
