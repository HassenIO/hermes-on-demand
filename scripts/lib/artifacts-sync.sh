#!/usr/bin/env bash
# Sourced by scripts/artifacts-sync.sh on the local machine. No SSH here.
#
# Three-way decision for one artifact, like git: base is the last synced copy,
# local is artifacts/<f>, remote is the live Hermes file. A missing path means
# the file does not exist on that side.

ARTIFACT_FILES=(SOUL.md USER.md MEMORY.md CV.md)

# Live path under HERMES_HOME, matching scripts/remote/install-artifacts.sh.
artifact_remote_path() {
  case "$1" in
    USER.md|MEMORY.md) printf 'memories/%s\n' "$1" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# Same normalization as install-artifacts.sh: LF endings, stripped, one newline.
artifact_normalize() {
  awk '
    { sub(/\r$/, ""); gsub(/\r/, "\n"); lines[NR] = $0 }
    END {
      s = 1; while (s <= NR && lines[s] ~ /^[[:space:]]*$/) s++
      e = NR; while (e >= s && lines[e] ~ /^[[:space:]]*$/) e--
      if (s > e) { print ""; exit }
      sub(/^[[:space:]]+/, "", lines[s]); sub(/[[:space:]]+$/, "", lines[e])
      for (i = s; i <= e; i++) print lines[i]
    }
  ' "$1"
}

artifact_has_conflict_markers() {
  grep -qE '^(<<<<<<<|>>>>>>>) ' "$1"
}

# Prints one of: same, pull, push, merged, conflict. Rewrites local on pull/merge.
artifact_sync_one() {
  local base="$1" local_f="$2" remote="$3"
  local tmp rc
  if [[ ! -f "$remote" ]]; then
    [[ -f "$local_f" ]] && echo push || echo same
    return 0
  fi
  if [[ ! -f "$local_f" ]]; then
    artifact_normalize "$remote" >"$local_f"
    echo pull
    return 0
  fi
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/hermes-artifact.XXXXXX")"
  artifact_normalize "$local_f" >"$tmp/local"
  artifact_normalize "$remote" >"$tmp/remote"
  if [[ -f "$base" ]]; then
    artifact_normalize "$base" >"$tmp/base"
  else
    : >"$tmp/base"
  fi
  if cmp -s "$tmp/local" "$tmp/remote"; then
    echo same
  elif [[ -f "$base" ]] && cmp -s "$tmp/local" "$tmp/base"; then
    cp "$tmp/remote" "$local_f"
    echo pull
  elif [[ -f "$base" ]] && cmp -s "$tmp/remote" "$tmp/base"; then
    echo push
  else
    rc=0
    git merge-file -p -L local -L base -L remote \
      "$tmp/local" "$tmp/base" "$tmp/remote" >"$tmp/merged" || rc=$?
    if ((rc < 0 || rc > 127)); then
      rm -rf "$tmp"
      die "git merge-file failed on $local_f"
    fi
    cp "$tmp/merged" "$local_f"
    ((rc == 0)) && echo merged || echo conflict
  fi
  rm -rf "$tmp"
}

# True when local still differs from remote, so a push is needed.
artifact_needs_push() {
  local local_f="$1" remote="$2"
  [[ -f "$local_f" ]] || return 1
  [[ -f "$remote" ]] || return 0
  ! cmp -s <(artifact_normalize "$local_f") <(artifact_normalize "$remote")
}
