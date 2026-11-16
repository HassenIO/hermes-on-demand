#!/usr/bin/env bash
# Shared Docker-runtime decisions. Sourced by local deploy and VPS scripts.
# Does not SSH. Does not start a container by itself.

if ! declare -F die >/dev/null 2>&1; then
  _hermes_docker_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=common.sh
  source "$_hermes_docker_lib_dir/common.sh"
  unset _hermes_docker_lib_dir
fi

_HERMES_DOCKER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Exact opt-in. true/yes/TRUE do not count. Not a runtime-env variable.
docker_runtime_requested() {
  [[ "${HERMES_DOCKER_RUNTIME:-}" == "1" ]]
}

# container | host. Flag-unset deploy and update stay on the host.
gateway_refresh_mode() {
  if docker_runtime_requested; then
    printf '%s\n' container
  else
    printf '%s\n' host
  fi
}

# Prefix a remote command only when the opt-in flag is exact 1.
with_docker_runtime_flag() {
  if docker_runtime_requested; then
    printf 'HERMES_DOCKER_RUNTIME=1 %s\n' "$1"
  else
    printf '%s\n' "$1"
  fi
}

hermes_compose_file() {
  local root
  root="$(cd "$_HERMES_DOCKER_LIB_DIR/../.." && pwd)"
  printf '%s\n' "$root/docker/hermes/docker-compose.yml"
}

hermes_docker_up_script() {
  printf '%s\n' "$_HERMES_DOCKER_LIB_DIR/../remote/hermes-docker-up.sh"
}

export_user_runtime_dir() {
  if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
  fi
}

unit_is_live_state() {
  case "$1" in
    active|activating|reloading|deactivating) return 0 ;;
    *) return 1 ;;
  esac
}

# Prints ActiveState. Returns 1 if systemctl cannot be queried. Does not exit.
read_gateway_unit_state() {
  local state
  export_user_runtime_dir
  state="$(systemctl --user show hermes-gateway --property=ActiveState --value 2>/dev/null)" || return 1
  state="${state//$'\r'/}"
  state="${state#"${state%%[![:space:]]*}"}"
  state="${state%"${state##*[![:space:]]}"}"
  [[ -n "$state" ]] || return 1
  printf '%s\n' "$state"
}

# Refuse a live unit. Does not stop or disable it.
require_gateway_unit_clear() {
  local state
  state="$(read_gateway_unit_state)" || die "cannot query hermes-gateway (systemctl --user failed); refusing to start a second writer"
  if unit_is_live_state "$state"; then
    die "hermes-gateway is ${state}; not stopping it. Stop that writer before retrying."
  fi
}

# Official gateway only. An unrelated container named hermes does not count.
container_is_official_gateway() {
  local image cmd running
  image="$(docker inspect -f '{{.Config.Image}}' hermes 2>/dev/null)" || return 1
  cmd="$(docker inspect -f '{{join .Config.Cmd " "}}' hermes 2>/dev/null)" || return 1
  running="$(docker inspect -f '{{.State.Running}}' hermes 2>/dev/null)" || return 1
  [[ "$running" == "true" ]] || return 1
  [[ "$cmd" == "gateway run" ]] || return 1
  image="${image#docker.io/}"
  case "$image" in
    nousresearch/hermes-agent|nousresearch/hermes-agent:*|nousresearch/hermes-agent@*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# 0 running, 1 not running, 2 process list failed.
host_gateway_process_running() {
  local line out
  out="$(ps -eo args= 2>/dev/null)" || return 2
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if [[ "$line" =~ (^|[[:space:]/])hermes[[:space:]]+gateway([[:space:]]|$) ]]; then
      return 0
    fi
  done <<<"$out"
  return 1
}

require_no_host_gateway_process() {
  local rc=0
  set +e
  host_gateway_process_running
  rc=$?
  set -e
  if [[ "$rc" -eq 2 ]]; then
    die "cannot list host processes; refusing to start a second writer"
  fi
  if [[ "$rc" -eq 0 ]]; then
    die "host hermes gateway process is running; not killing it. Stop that writer before retrying."
  fi
}

# Exact data directory, or a parent of it. A child (terminal sandbox mounts
# such as memories or content) is not a second writer.
mount_covers_data() {
  local source="$1"
  local data="$2"
  source="${source%/}"
  data="${data%/}"
  [[ -n "$source" && -n "$data" ]] || return 1
  [[ "$source" == "$data" ]] && return 0
  [[ "$data" == "$source"/* ]] && return 0
  return 1
}

container_name_is_ours() {
  case "$1" in
    hermes|/hermes) return 0 ;;
    *) return 1 ;;
  esac
}

# Another container (running or stopped) whose mount is the data dir or a parent of it.
require_no_foreign_data_mount() {
  local data="$1"
  local ids id name mounts line source dest
  ids="$(docker ps -aq)" || die "docker ps failed; refusing to start a second writer"
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    name="$(docker inspect -f '{{.Name}}' "$id")" || die "docker inspect failed for $id; refusing to start a second writer"
    if container_name_is_ours "$name"; then
      continue
    fi
    mounts="$(docker inspect -f '{{range .Mounts}}{{.Source}} {{.Destination}}{{"\n"}}{{end}}' "$id")" \
      || die "docker inspect mounts failed for $id; refusing to start a second writer"
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      source="${line%% *}"
      dest="${line#* }"
      if mount_covers_data "$source" "$data"; then
        die "container ${name} mounts ${source} -> ${dest} over ${data}; not starting a second writer"
      fi
    done <<<"$mounts"
  done <<<"$ids"
}

refuse_root_owned_data_dir() {
  local dir="$1"
  local uid
  uid="$(stat -c %u "$dir")" || die "cannot stat owner of $dir"
  if [[ "$uid" != "0" ]]; then
    return 0
  fi
  if [[ -e "$dir/state.db" ]] || [[ -n "$(find "$dir/sessions" -type f -print -quit 2>/dev/null)" ]]; then
    die "refusing root-owned $dir that already has sessions; not chowning to UID 10000"
  fi
  prepare_non_root_owner "$dir"
}

# Fresh root SSH has no non-root owner. Create one. Do not use UID 10000.
prepare_non_root_owner() {
  local dir="$1"
  local h_uid h_gid
  if ! id hermes >/dev/null 2>&1; then
    useradd --system --create-home --shell /usr/sbin/nologin hermes \
      || die "cannot create non-root hermes user for $dir"
  fi
  h_uid="$(id -u hermes)"
  h_gid="$(id -g hermes)"
  if [[ -z "$h_uid" || "$h_uid" == "0" ]]; then
    die "hermes user is uid 0; not chowning to UID 10000"
  fi
  chown -R "${h_uid}:${h_gid}" "$dir" || die "cannot give $dir to hermes user"
  log "fresh root-owned $dir now owned by hermes (${h_uid}:${h_gid}), not UID 10000"
}

# Image stage2 runs as root and can leave new files owned by uid 0.
# Give those to the data-dir owner. Never to UID 10000.
reclaim_root_owned_files() {
  local dir="$1"
  local uid gid path found=0
  uid="$(stat -c %u "$dir")" || return 1
  gid="$(stat -c %g "$dir")" || return 1
  [[ "$uid" != "0" && -n "$uid" ]] || return 1
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    chown "${uid}:${gid}" "$path" || return 1
    found=1
  done < <(find "$dir" -user 0 -print)
  [[ "$found" -eq 1 ]]
}

# Run a command where the gateway runs. With the official container up, that is
# inside it as the data-dir owner with the runtime env: root SSH on the host would
# leave root-owned files and reads the host install, not the gateway's.
run_in_gateway() {
  local home="${HERMES_HOME:-$HOME/.hermes}"
  local uid gid
  if container_is_official_gateway; then
    read -r uid gid <<<"$(data_dir_owner_ids "$home")"
    docker exec -u "${uid}:${gid}" --env-file "$home/.env" hermes "$@"
    return
  fi
  "$@"
}

# The Mnemosyne side-venv is built on the image's Python and cannot start on the
# host, so with the container up it runs there (container path of the same venv).
run_mnemosyne() {
  local home="${HERMES_HOME:-$HOME/.hermes}"
  if container_is_official_gateway; then
    run_in_gateway /opt/data/.mnemosyne/venv/bin/mnemosyne "$@"
    return
  fi
  "${MNEMOSYNE_VENV:-$home/.mnemosyne/venv}/bin/mnemosyne" "$@"
}

data_dir_owner_ids() {
  local dir="$1"
  local uid gid
  uid="$(stat -c %u "$dir")" || die "cannot stat uid of $dir"
  gid="$(stat -c %g "$dir")" || die "cannot stat gid of $dir"
  printf '%s %s\n' "$uid" "$gid"
}

require_docker_socket() {
  local sock="${1:-${HERMES_DOCKER_SOCK:-/var/run/docker.sock}}"
  if [[ ! -S "$sock" ]]; then
    die "missing ${sock}; refusing to let compose create a directory there"
  fi
}

expand_mount_token() {
  local p="$1"
  local home="$2"
  p="${p//\$\{HERMES_HOME\}/$home}"
  p="${p//\$HERMES_HOME/$home}"
  p="${p//\$\{HOME\}/$HOME}"
  p="${p//\$HOME/$HOME}"
  if [[ "$p" == "~" ]]; then
    p="$HOME"
  elif [[ "$p" == "~/"* ]]; then
    p="$HOME/${p:2}"
  fi
  printf '%s\n' "$p"
}

compose_volume_lines() {
  local file="$1"
  local in=0 vol_indent=0 line indent item
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*# ]]; then
      continue
    fi
    if [[ "$line" =~ ^([[:space:]]*)volumes:[[:space:]]*$ ]]; then
      in=1
      vol_indent=${#BASH_REMATCH[1]}
      continue
    fi
    if [[ "$in" -eq 1 ]]; then
      if [[ "$line" =~ ^([[:space:]]*)[^[:space:]] ]]; then
        indent=${#BASH_REMATCH[1]}
        if (( indent <= vol_indent )); then
          in=0
        fi
      fi
    fi
    if [[ "$in" -eq 1 && "$line" =~ ^[[:space:]]+-[[:space:]]+(.+)$ ]]; then
      item="${BASH_REMATCH[1]}"
      item="${item%"${item##*[![:space:]]}"}"
      printf '%s\n' "$item"
    fi
  done < "$file"
}

compose_has_forbidden_key() {
  local file="$1"
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    case "$line" in
      *"HERMES_DASHBOARD"*|*"hermes-agent="*|*"umask"*)
        return 0
        ;;
    esac
    if [[ "$line" =~ ^[[:space:]]*ports:[[:space:]]*$ ]]; then
      return 0
    fi
    if [[ "$line" =~ ^[[:space:]]*user:[[:space:]] ]]; then
      return 0
    fi
  done < "$file"
  return 1
}

# Directory bind of the existing home to /opt/data, plus the docker socket.
# Rejects a file mount, a named volume, and a different directory.
assert_hermes_compose_mounts() {
  local compose="$1"
  local home="$2"
  local line source dest rest found_data=0 found_sock=0
  [[ -f "$compose" ]] || die "missing compose file: $compose"
  [[ -d "$home" ]] || die "data dir is not a directory: $home"
  home="$(cd "$home" && pwd)"
  if compose_has_forbidden_key "$compose"; then
    die "compose publishes a port, sets a user, enables the dashboard, or labels hermes-agent"
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    line="${line#\"}"
    line="${line%\"}"
    line="${line#\'}"
    line="${line%\'}"
    if [[ "$line" != *:* ]]; then
      die "compose named volume is not a directory bind: $line"
    fi
    source="${line%%:*}"
    rest="${line#*:}"
    dest="${rest%%:*}"
    source="$(expand_mount_token "$source" "$home")"
    dest="$(expand_mount_token "$dest" "$home")"
    if [[ "$source" != /* ]]; then
      die "compose named volume is not a directory bind: $line"
    fi
    if [[ "$dest" == "/var/run/docker.sock" && "$source" == */docker.sock ]]; then
      found_sock=1
      continue
    fi
    if [[ -f "$source" ]]; then
      die "compose bind-mounts a file ($source); refusing a single-file mount"
    fi
    if [[ "$dest" != "/opt/data" ]]; then
      die "compose bind ($source -> $dest) is not the data directory mount"
    fi
    if [[ "$source" != "$home" ]]; then
      die "compose data mount $source is not the existing data dir $home"
    fi
    if [[ ! -d "$source" ]]; then
      die "compose data mount is not a directory: $source"
    fi
    found_data=1
  done < <(compose_volume_lines "$compose")
  [[ "$found_data" -eq 1 ]] || die "compose is missing a directory bind of $home to /opt/data"
  [[ "$found_sock" -eq 1 ]] || die "compose is missing the docker socket mount"
}

# Create the symlink only when starting the container. Never retarget.
# HERMES_OPT_DATA_CREATED=1 only when this call creates the link.
ensure_opt_data_symlink() {
  local target="$1"
  local link="${2:-${HERMES_OPT_DATA_LINK:-/opt/data}}"
  local current resolved parent
  target="$(cd "$target" && pwd)"
  HERMES_OPT_DATA_CREATED=0
  if [[ -L "$link" ]]; then
    current="$(readlink "$link")"
    if [[ "$current" == "$target" ]]; then
      return 0
    fi
    resolved="$(readlink -f "$link" 2>/dev/null || true)"
    if [[ "$resolved" == "$target" ]]; then
      return 0
    fi
    die "refusing to retarget $link (points at ${current}, want ${target})"
  fi
  if [[ -e "$link" ]]; then
    die "refusing to replace $link (not a symlink to ${target})"
  fi
  parent="$(dirname "$link")"
  if [[ -w "$parent" ]]; then
    ln -s "$target" "$link"
  else
    sudo -n ln -s "$target" "$link" || die "cannot create $link (parent not writable)"
  fi
  HERMES_OPT_DATA_CREATED=1
}

remove_opt_data_symlink_if_created() {
  local link="${1:-${HERMES_OPT_DATA_LINK:-/opt/data}}"
  [[ "${HERMES_OPT_DATA_CREATED:-}" == "1" ]] || return 0
  [[ -L "$link" ]] || return 0
  if [[ -w "$(dirname "$link")" ]]; then
    rm "$link"
  else
    sudo -n rm "$link" || true
  fi
  HERMES_OPT_DATA_CREATED=0
}

pull_hermes_image() {
  local compose="$1"
  docker compose -f "$compose" pull
}

# Pull only when the official image is not already local. Never --pull always.
ensure_hermes_image() {
  if ! docker image inspect nousresearch/hermes-agent >/dev/null 2>&1; then
    docker pull nousresearch/hermes-agent
  fi
}

# Ordinary recreate. No --pull always. No down -v.
recreate_hermes_container() {
  local compose="$1"
  ensure_hermes_image
  docker compose -f "$compose" up -d --force-recreate --no-deps --pull never
}

disable_host_gateway_unit() {
  local enabled
  export_user_runtime_dir
  local state
  state="$(read_gateway_unit_state)" || die "cannot query hermes-gateway after container start"
  if unit_is_live_state "$state"; then
    die "hermes-gateway became ${state} while the container started; not stopping it"
  fi
  systemctl --user disable hermes-gateway >/dev/null 2>&1 || true
  enabled="$(systemctl --user is-enabled hermes-gateway 2>/dev/null || true)"
  [[ -n "$enabled" ]] || die "cannot query whether hermes-gateway is enabled"
  case "$enabled" in
    enabled|enabled-runtime|linked|linked-runtime|alias)
      die "hermes-gateway is still enabled (${enabled}); reboot would start a second writer"
      ;;
  esac
}

require_gateway_files() {
  local dir="$1"
  [[ -f "$dir/.env" ]] || die "missing $dir/.env; not seeding secrets"
  [[ -f "$dir/config.yaml" ]] || die "missing $dir/config.yaml; not seeding config"
}

# Opt-in bootstrap: do not install or start the user unit.
install_host_gateway_unless_docker() {
  local log_dir="${HERMES_HOME:-$HOME/.hermes}/logs"
  if docker_runtime_requested; then
    log "HERMES_DOCKER_RUNTIME=1: not installing or starting hermes-gateway"
    return 0
  fi
  if hermes_container_running || hermes_container_present; then
    die "refusing to install or start hermes-gateway while container hermes exists"
  fi
  log "Installing gateway service (user unit)"
  hermes gateway install || true
  if command -v loginctl >/dev/null 2>&1; then
    if loginctl enable-linger "$USER" 2>/dev/null; then
      log "Linger enabled for $USER"
    elif sudo loginctl enable-linger "$USER" 2>/dev/null; then
      log "Linger enabled for $USER (via sudo)"
    else
      warn "Could not enable linger; gateway may stop on logout"
    fi
  fi
  log "Starting gateway"
  if ! start_host_gateway; then
    if hermes_container_running; then
      die "refusing nohup gateway while container hermes is running"
    fi
    warn "service start helpers failed; trying hermes gateway in background"
    mkdir -p "$log_dir"
    nohup hermes gateway >>"$log_dir/gateway.nohup.log" 2>&1 &
    sleep 2
  fi
}

# Docker path pulls then recreates. Host path runs hermes update. Patch failure does not abort recreate.
run_hermes_upgrade() {
  local patch_script="${1:-}"
  local compose="${2:-}"
  local up_script="${3:-}"
  if docker_runtime_requested; then
    log "Docker runtime: pull image and recreate (not hermes update)"
    if [[ -n "$patch_script" && -f "$patch_script" ]]; then
      if ! bash "$patch_script"; then
        warn "host colon-path patch failed; image code is immutable, continuing recreate"
      fi
    fi
    [[ -n "$compose" ]] || die "missing compose path for image pull"
    pull_hermes_image "$compose"
    [[ -n "$up_script" ]] || die "missing up script for recreate"
    bash "$up_script"
    return 0
  fi
  log "Running hermes update"
  hermes update || warn "hermes update exited non-zero — continuing with repair steps"
}

# 0 container is the only writer, 1 two writers or query failed, host path returns 2 via the host checks' own code.
# Returns 0 on a healthy single writer, 1 when the gateway is missing or doubled.
apply_gateway_health() {
  local state proc=1
  if container_is_official_gateway; then
    if ! state="$(read_gateway_unit_state)"; then
      warn "FAIL gateway: container hermes is up and hermes-gateway cannot be queried"
      return 1
    fi
    set +e
    host_gateway_process_running
    proc=$?
    set -e
    if [[ "$proc" -eq 2 ]]; then
      warn "FAIL gateway: container hermes is up and host process list failed"
      return 1
    fi
    if unit_is_live_state "$state" || [[ "$proc" -eq 0 ]]; then
      warn "FAIL two gateway writers: container hermes and host (unit=${state})"
      return 1
    fi
    log "OK  gateway container hermes (nousresearch/hermes-agent gateway run)"
    return 0
  fi
  if ! command -v hermes >/dev/null 2>&1; then
    return 1
  fi
  if hermes gateway status >/dev/null 2>&1; then
    log "OK  gateway status"
    hermes gateway status || true
    return 0
  fi
  warn "gateway status failed"
  hermes gateway status || true
  if pgrep -af 'hermes.*gateway' >/dev/null 2>&1; then
    log "OK  gateway process found"
    return 0
  fi
  return 1
}

refresh_gateway() {
  local up
  if docker_runtime_requested; then
    up="$(hermes_docker_up_script)"
    bash "$up"
    return
  fi
  start_host_gateway
  hermes gateway status 2>/dev/null || true
}

# Deploy flag arm. ssh_cmd is deploy.sh's, or a test stub. Host command is
# optional: full deploy already started the unit when the flag is unset.
gateway_refresh_ssh() {
  local remote_dir="${1:?}"
  local host_command="${2:-}"
  case "$(gateway_refresh_mode)" in
    container)
      ssh_cmd "$(with_docker_runtime_flag "bash '${remote_dir}/scripts/remote/hermes-docker-up.sh'")"
      ;;
    host)
      if [[ -n "$host_command" ]]; then
        ssh_cmd "$host_command"
      fi
      ;;
  esac
}
