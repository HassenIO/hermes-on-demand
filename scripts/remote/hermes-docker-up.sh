#!/usr/bin/env bash
# Runs ON the VPS. Start the official Hermes image against the existing data dir.
# Idempotent. Does not delete host state. Does not stop hermes-gateway on the refuse path.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/hermes-docker.sh
source "$SCRIPT_DIR/../lib/hermes-docker.sh"

hermes_docker_up_main() {
  local home compose sock link uid gid
  home="${HERMES_HOME:-$HOME/.hermes}"
  sock="${HERMES_DOCKER_SOCK:-/var/run/docker.sock}"
  link="${HERMES_OPT_DATA_LINK:-/opt/data}"
  mkdir -p "$home"
  home="$(cd "$home" && pwd)"
  export HERMES_HOME="$home"
  require_gateway_files "$home"
  refuse_root_owned_data_dir "$home"
  read -r uid gid <<<"$(data_dir_owner_ids "$home")"
  export HERMES_PUID="$uid"
  export HERMES_PGID="$gid"
  # Cron schedules are local time. The container libc must see the same zone.
  local tz
  tz="$(grep -E '^TZ=' "$home/.env" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '"' || true)"
  export TZ="${tz:-${TZ:-UTC}}"
  require_docker_socket "$sock"
  compose="$(hermes_compose_file)"
  assert_hermes_compose_mounts "$compose" "$home"
  ensure_opt_data_symlink "$home" "$link"
  local started rc=0
  started="$(mktemp)"
  rm -f "$started"
  (
    require_gateway_unit_clear
    require_no_host_gateway_process
    require_no_foreign_data_mount "$home"
    recreate_hermes_container "$compose"
    touch "$started"
    container_is_official_gateway || die "container hermes is not running nousresearch/hermes-agent gateway run"
    if reclaim_root_owned_files "$home"; then
      log "reclaimed root-owned files under $home for the data-dir owner"
      docker restart hermes >/dev/null
      container_is_official_gateway || die "container hermes did not return after ownership reclaim"
    fi
    disable_host_gateway_unit
  ) || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    remove_opt_data_symlink_if_created "$link"
    if [[ -f "$started" ]]; then
      docker stop hermes >/dev/null 2>&1 || true
    fi
    rm -f "$started"
    exit "$rc"
  fi
  rm -f "$started"
  log "gateway container hermes is up (nousresearch/hermes-agent gateway run); host unit disabled"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  hermes_docker_up_main "$@"
fi
