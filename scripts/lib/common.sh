#!/usr/bin/env bash
# Shared helpers for Mac deploy and remote bootstrap.

set -euo pipefail

log()  { printf '==> %s\n' "$*"; }
warn() { printf '!!  %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Load KEY=VAL from a dotenv file into the current shell.
# Supports optional double/single quotes; ignores blank lines and comments.
load_dotenv() {
  local file="${1:?dotenv path required}"
  [[ -f "$file" ]] || die "missing env file: $file"
  local line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == export\ * ]] && line="${line#export }"
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    val="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    key="${key#"${key%%[![:space:]]*}"}"
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    if [[ "$val" == \"*\" && "$val" == *\" ]]; then
      val="${val:1:${#val}-2}"
    elif [[ "$val" == \'*\' && "$val" == *\' ]]; then
      val="${val:1:${#val}-2}"
    fi
    printf -v "$key" '%s' "$val"
    export "$key"
  done < "$file"
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
