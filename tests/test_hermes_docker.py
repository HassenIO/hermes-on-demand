"""Docker runtime guards. Executes the decision functions; no SSH and no daemon."""

from __future__ import annotations

import os
import shutil
import stat
import subprocess
import tempfile
import textwrap
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "scripts" / "lib" / "hermes-docker.sh"
UP = ROOT / "scripts" / "remote" / "hermes-docker-up.sh"
UPDATE = ROOT / "scripts" / "remote" / "hermes-update.sh"
COMPOSE = ROOT / "docker" / "hermes" / "docker-compose.yml"

DOCKER_STUB = """#!/bin/sh
echo "$*" >> "$STUB_LOG"
if [ "$1" = "ps" ]; then
  if [ "${DOCKER_PS_RC:-0}" != "0" ]; then
    exit "$DOCKER_PS_RC"
  fi
  if [ -n "${DOCKER_PS_IDS:-}" ]; then
    printf '%s\\n' "$DOCKER_PS_IDS"
  fi
  exit 0
fi
if [ "$1" = "inspect" ]; then
  fmt=""
  prev=""
  for arg in "$@"; do
    if [ "$prev" = "-f" ]; then
      fmt="$arg"
    fi
    prev="$arg"
  done
  if [ -z "$fmt" ]; then
    if [ -n "${DOCKER_RUNNING+x}" ]; then
      exit 0
    fi
    exit 1
  fi
  case "$fmt" in
    *Config.Image*)
      printf '%s\\n' "${DOCKER_IMAGE:-nousresearch/hermes-agent}"
      ;;
    *Config.Cmd*)
      printf '%s\\n' "${DOCKER_CMD:-gateway run}"
      ;;
    *State.Running*)
      if [ -z "${DOCKER_RUNNING+x}" ]; then
        exit 1
      fi
      printf '%s\\n' "$DOCKER_RUNNING"
      ;;
    *'.Name'*)
      printf '%s\\n' "${DOCKER_INSPECT_NAME:-/other}"
      ;;
    *Mounts*)
      printf '%s\\n' "${DOCKER_INSPECT_MOUNTS:-}"
      ;;
    *)
      echo "unhandled inspect: $fmt" >&2
      exit 1
      ;;
  esac
  exit 0
fi
if [ "$1" = "compose" ]; then
  exit "${DOCKER_COMPOSE_RC:-0}"
fi
if [ "$1" = "image" ]; then
  exit "${DOCKER_IMAGE_INSPECT_RC:-0}"
fi
if [ "$1" = "pull" ] || [ "$1" = "stop" ] || [ "$1" = "exec" ]; then
  exit 0
fi
echo "unhandled docker: $*" >&2
exit 1
"""

SYSTEMCTL_STUB = """#!/bin/sh
echo "$*" >> "$STUB_LOG"
if [ "${SYSTEMCTL_RC:-0}" != "0" ]; then
  exit "$SYSTEMCTL_RC"
fi
case "$*" in
  *stop*)
    echo "systemctl stop must not run" >&2
    exit 99
    ;;
  *is-enabled*)
    printf '%s\\n' "${SYSTEMCTL_ENABLED:-disabled}"
    ;;
  *show*)
    if [ -z "${SYSTEMCTL_STATE+x}" ]; then
      printf '%s\\n' inactive
    else
      printf '%s\\n' "$SYSTEMCTL_STATE"
    fi
    ;;
  *)
    exit 0
    ;;
esac
"""

STAT_STUB = """#!/bin/sh
echo "$*" >> "$STUB_LOG"
case "$*" in
  *%u*) printf '%s\\n' "${STAT_UID:-1000}" ;;
  *%g*) printf '%s\\n' "${STAT_GID:-1000}" ;;
  *) echo "unhandled stat: $*" >&2; exit 1 ;;
esac
"""

PS_STUB = """#!/bin/sh
echo "$*" >> "$STUB_LOG"
if [ "${PS_RC:-0}" != "0" ]; then
  exit "$PS_RC"
fi
printf '%s\\n' "${PS_LINES:-bash unit-test}"
exit 0
"""

HERMES_STUB = """#!/bin/sh
echo "$*" >> "$HERMES_LOG"
exit "${HERMES_RC:-0}"
"""

PGREP_STUB = """#!/bin/sh
echo "$*" >> "$STUB_LOG"
exit 1
"""


def write_exe(path: Path, body: str) -> None:
    path.write_text(textwrap.dedent(body))
    path.chmod(path.stat().st_mode | stat.S_IEXEC)


def make_env(tmp: Path, **extra: str) -> dict[str, str]:
    bindir = tmp / "bin"
    bindir.mkdir(parents=True, exist_ok=True)
    write_exe(bindir / "docker", DOCKER_STUB)
    write_exe(bindir / "systemctl", SYSTEMCTL_STUB)
    write_exe(bindir / "stat", STAT_STUB)
    write_exe(bindir / "ps", PS_STUB)
    write_exe(bindir / "hermes", HERMES_STUB)
    write_exe(bindir / "pgrep", PGREP_STUB)
    env = {
        "PATH": str(bindir) + os.pathsep + os.environ.get("PATH", ""),
        "HOME": str(tmp / "user"),
        "USER": "tester",
        "STUB_LOG": str(tmp / "stub.log"),
        "HERMES_LOG": str(tmp / "hermes.log"),
        "HERMES_OPT_DATA_LINK": str(tmp / "opt-data"),
        "HERMES_DOCKER_SOCK": str(tmp / "docker.sock"),
    }
    (tmp / "user").mkdir(parents=True, exist_ok=True)
    env.update(extra)
    return env


def run(script: str, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", "-c", script],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
    )


def source_lib(body: str) -> str:
    return f'set -euo pipefail\nsource "{LIB}"\n{body}\n'


@pytest.fixture
def sock():
    # macOS AF_UNIX paths must stay under 104 bytes. pytest's tmp_path does not.
    short = Path(tempfile.mkdtemp(prefix="hs", dir="/tmp"))
    path = short / "s"
    subprocess.run(
        [
            "python3",
            "-c",
            "import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])",
            str(path),
        ],
        check=True,
    )
    yield path
    shutil.rmtree(short, ignore_errors=True)


def ready_home(tmp: Path) -> Path:
    home = tmp / "user" / ".hermes"
    home.mkdir(parents=True)
    (home / ".env").write_text("OPENROUTER_API_KEY=test\n")
    (home / "config.yaml").write_text("model:\n  default: xiaomi/mimo-v2.5\n")
    return home


@pytest.fixture
def box(tmp_path: Path):
    return tmp_path


def test_opt_in_flag_and_refresh_mode(box: Path) -> None:
    script = source_lib(
        """
if docker_runtime_requested; then echo requested; else echo skipped; fi
echo "mode=$(gateway_refresh_mode)"
printf 'prefix=%s' "$(with_docker_runtime_flag "bash hermes-docker-up.sh")"
"""
    )
    off = run(script, make_env(box / "off"))
    assert off.returncode == 0, off.stderr
    assert "skipped" in off.stdout
    assert "mode=host" in off.stdout
    assert "HERMES_DOCKER_RUNTIME" not in off.stdout
    assert "hermes-docker-up.sh" in off.stdout

    on = run(script, make_env(box / "on", HERMES_DOCKER_RUNTIME="1"))
    assert on.returncode == 0, on.stderr
    assert "requested" in on.stdout
    assert "mode=container" in on.stdout
    assert on.stdout.split("prefix=", 1)[1].startswith("HERMES_DOCKER_RUNTIME=1 ")

    other = run(script, make_env(box / "true", HERMES_DOCKER_RUNTIME="true"))
    assert other.returncode == 0, other.stderr
    assert "skipped" in other.stdout
    assert "mode=host" in other.stdout
    assert "HERMES_DOCKER_RUNTIME" not in other.stdout


def test_committed_compose_is_a_directory_bind(box: Path) -> None:
    home = ready_home(box)
    script = source_lib(
        f"""
assert_hermes_compose_mounts "{COMPOSE}" "{home}"
echo ok
"""
    )
    result = run(script, make_env(box, HOME=str(box / "user")))
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "ok"
    text = COMPOSE.read_text()
    assert "nousresearch/hermes-agent" in text
    assert "gateway run" in text
    assert "network_mode: host" in text


def test_single_file_mount_refused(box: Path) -> None:
    home = ready_home(box)
    secret = home / ".env"
    compose = box / "bad.yml"
    compose.write_text(
        "services:\n  hermes:\n    volumes:\n"
        f"      - {secret}:/opt/data/.env\n"
        "      - /var/run/docker.sock:/var/run/docker.sock\n"
    )
    script = source_lib(f'assert_hermes_compose_mounts "{compose}" "{home}"\n')
    result = run(script, make_env(box, HOME=str(box / "user")))
    assert result.returncode != 0
    assert "bind-mounts a file" in result.stderr
    assert str(secret) in result.stderr


def test_home_expanded_single_file_mount_refused(box: Path) -> None:
    user = box / "user"
    data = user / ".hermes"
    data.mkdir(parents=True)
    (data / "auth.json").write_text("{}\n")
    (data / ".env").write_text("K=v\n")
    (data / "config.yaml").write_text("model: {}\n")
    compose = box / "home.yml"
    compose.write_text(
        "services:\n  hermes:\n    volumes:\n"
        "      - $HOME/.hermes/auth.json:/opt/data/auth.json\n"
        "      - /var/run/docker.sock:/var/run/docker.sock\n"
    )
    script = source_lib(f'assert_hermes_compose_mounts "{compose}" "{data}"\n')
    result = run(script, make_env(box, HOME=str(user)))
    assert result.returncode != 0
    assert "bind-mounts a file" in result.stderr
    assert str(data / "auth.json") in result.stderr
    assert "named volume" not in result.stderr


def test_named_volume_and_fresh_directory_refused(box: Path) -> None:
    home = ready_home(box)
    other = box / "fresh"
    other.mkdir()
    named = box / "named.yml"
    named.write_text(
        "services:\n  hermes:\n    volumes:\n"
        "      - hermes-data:/opt/data\n"
        "      - /var/run/docker.sock:/var/run/docker.sock\n"
    )
    fresh = box / "fresh.yml"
    fresh.write_text(
        "services:\n  hermes:\n    volumes:\n"
        f"      - {other}:/opt/data\n"
        "      - /var/run/docker.sock:/var/run/docker.sock\n"
    )
    named_result = run(
        source_lib(f'assert_hermes_compose_mounts "{named}" "{home}"\n'),
        make_env(box / "n", HOME=str(box / "user")),
    )
    assert named_result.returncode != 0
    assert "named volume" in named_result.stderr
    fresh_result = run(
        source_lib(f'assert_hermes_compose_mounts "{fresh}" "{home}"\n'),
        make_env(box / "f", HOME=str(box / "user")),
    )
    assert fresh_result.returncode != 0
    assert "not the existing data dir" in fresh_result.stderr


def test_recreate_does_not_pull_always_or_down_v(box: Path) -> None:
    script = source_lib(f'recreate_hermes_container "{COMPOSE}"\n')
    result = run(script, make_env(box))
    assert result.returncode == 0, result.stderr
    log = (box / "stub.log").read_text()
    assert "compose" in log
    assert "up" in log
    assert "--pull never" in log
    assert "--pull always" not in log
    assert "down" not in log
    assert " -v" not in log
    assert "pull nousresearch/hermes-agent" not in log


def test_uid_zero_with_sessions_refused_without_chown(box: Path) -> None:
    home = ready_home(box)
    (home / "state.db").write_text("keep\n")
    script = source_lib(f'refuse_root_owned_data_dir "{home}"\necho should-not-run\n')
    result = run(script, make_env(box, STAT_UID="0", HOME=str(box / "user")))
    assert result.returncode != 0
    assert "root-owned" in result.stderr
    assert "should-not-run" not in result.stdout
    assert (home / "state.db").read_text() == "keep\n"
    assert "chown" not in (box / "stub.log").read_text()


def test_uid_zero_fresh_tree_gets_non_root_owner(box: Path) -> None:
    home = ready_home(box)
    (home / "sessions").mkdir()
    env = make_env(box, STAT_UID="0", HOME=str(box / "user"))
    bindir = box / "bin"
    write_exe(
        bindir / "id",
        "#!/bin/sh\n"
        'echo "$*" >> "$STUB_LOG"\n'
        'if [ "$1" = "-u" ]; then echo 987; exit 0; fi\n'
        'if [ "$1" = "-g" ]; then echo 987; exit 0; fi\n'
        "exit 1\n",
    )
    write_exe(
        bindir / "useradd",
        "#!/bin/sh\necho \"$*\" >> \"$STUB_LOG\"\nexit 0\n",
    )
    write_exe(
        bindir / "chown",
        "#!/bin/sh\necho \"$*\" >> \"$STUB_LOG\"\nexit 0\n",
    )
    script = source_lib(f'refuse_root_owned_data_dir "{home}"\necho prepared\n')
    result = run(script, env)
    assert result.returncode == 0, result.stderr
    assert "prepared" in result.stdout
    log = (box / "stub.log").read_text()
    assert "--system" in log
    assert "-R 987:987" in log
    assert "10000" not in log


def test_wrong_opt_data_symlink_not_retargeted(box: Path) -> None:
    home = ready_home(box)
    other = box / "elsewhere"
    other.mkdir()
    link = box / "opt-data"
    link.symlink_to(other)
    script = source_lib(
        f'ensure_opt_data_symlink "{home}" "{link}"\necho should-not-run\n'
    )
    result = run(script, make_env(box, HOME=str(box / "user")))
    assert result.returncode != 0
    assert "refusing to retarget" in result.stderr
    assert link.is_symlink()
    assert os.path.realpath(link) == str(other)
    assert "should-not-run" not in result.stdout


def test_matching_symlink_kept_and_missing_one_created(box: Path) -> None:
    home = ready_home(box)
    link = box / "opt-data"
    link.symlink_to(home)
    kept = run(
        source_lib(f'ensure_opt_data_symlink "{home}" "{link}"\necho kept\n'),
        make_env(box / "kept", HOME=str(box / "user")),
    )
    assert kept.returncode == 0, kept.stderr
    assert os.path.realpath(link) == str(home.resolve())

    missing = box / "new-link"
    created = run(
        source_lib(f'ensure_opt_data_symlink "{home}" "{missing}"\n'),
        make_env(box / "new", HOME=str(box / "user")),
    )
    assert created.returncode == 0, created.stderr
    assert missing.is_symlink()
    assert os.path.realpath(missing) == str(home.resolve())


@pytest.mark.parametrize("state", ["active", "activating", "reloading", "deactivating"])
def test_live_unit_refuses_without_stop(box: Path, state: str) -> None:
    script = source_lib("require_gateway_unit_clear\necho should-not-run\n")
    env = make_env(box / state, SYSTEMCTL_STATE=state)
    result = run(script, env)
    assert result.returncode != 0
    assert state in result.stderr
    assert "not stopping" in result.stderr
    assert "should-not-run" not in result.stdout
    log = (box / state / "stub.log").read_text()
    assert "stop" not in log
    assert "disable" not in log


def test_systemctl_failure_and_empty_state_fail_closed(box: Path) -> None:
    failed = run(
        source_lib("require_gateway_unit_clear\n"),
        make_env(box / "rc", SYSTEMCTL_RC="1"),
    )
    assert failed.returncode != 0
    assert "cannot query" in failed.stderr
    empty = run(
        source_lib("require_gateway_unit_clear\n"),
        make_env(box / "empty", SYSTEMCTL_STATE=""),
    )
    assert empty.returncode != 0
    assert "cannot query" in empty.stderr


def test_inactive_and_failed_units_are_clear(box: Path) -> None:
    for state in ("inactive", "failed"):
        result = run(
            source_lib("require_gateway_unit_clear\necho clear\n"),
            make_env(box / state, SYSTEMCTL_STATE=state),
        )
        assert result.returncode == 0, result.stderr
        assert "clear" in result.stdout


def test_host_start_refuses_running_container(box: Path) -> None:
    script = source_lib("start_host_gateway\necho should-not-run\n")
    result = run(script, make_env(box, DOCKER_RUNNING="true"))
    assert result.returncode != 0
    assert "container hermes is running" in result.stderr
    assert "should-not-run" not in result.stdout
    assert not (box / "hermes.log").exists()


def test_host_start_refuses_stopped_container(box: Path) -> None:
    result = run(
        source_lib("start_host_gateway\necho should-not-run\n"),
        make_env(box, DOCKER_RUNNING="false"),
    )
    assert result.returncode != 0
    assert "container hermes exists" in result.stderr
    assert "should-not-run" not in result.stdout
    assert not (box / "hermes.log").exists()


def test_host_start_runs_when_container_absent(box: Path) -> None:
    result = run(
        source_lib("start_host_gateway\n"),
        make_env(box),
    )
    assert result.returncode == 0, result.stderr
    assert "gateway restart" in (box / "hermes.log").read_text()


def test_bootstrap_skips_install_only_when_flag_is_one(box: Path) -> None:
    script = source_lib("install_host_gateway_unless_docker\n")
    opted = run(script, make_env(box / "on", HERMES_DOCKER_RUNTIME="1"))
    assert opted.returncode == 0, opted.stderr
    assert "not installing or starting" in opted.stdout
    assert not (box / "on" / "hermes.log").exists()

    host = run(script, make_env(box / "off"))
    assert host.returncode == 0, host.stderr
    assert "gateway install" in (box / "off" / "hermes.log").read_text()

    beside = run(
        script,
        make_env(box / "beside", DOCKER_RUNNING="true"),
    )
    assert beside.returncode != 0
    assert "container hermes exists" in beside.stderr
    assert not (box / "beside" / "hermes.log").exists()


def test_update_pulls_on_docker_path_and_hermes_update_on_host(box: Path) -> None:
    patch = box / "patch.sh"
    patch.write_text("#!/bin/sh\nexit 1\n")
    patch.chmod(0o755)
    marker = box / "up-called"
    up = box / "up.sh"
    up.write_text(f"#!/bin/sh\ntouch '{marker}'\n")
    up.chmod(0o755)
    script = source_lib(
        f'run_hermes_upgrade "{patch}" "{COMPOSE}" "{up}"\n'
    )
    docker_path = run(
        script,
        make_env(box / "docker", HERMES_DOCKER_RUNTIME="1"),
    )
    assert docker_path.returncode == 0, docker_path.stderr
    assert marker.is_file()
    log = (box / "docker" / "stub.log").read_text()
    assert "compose" in log and "pull" in log
    assert "--pull always" not in log
    assert "down" not in log
    assert not (box / "docker" / "hermes.log").exists()
    assert "continuing recreate" in docker_path.stderr

    host = run(script, make_env(box / "host"))
    assert host.returncode == 0, host.stderr
    assert "update" in (box / "host" / "hermes.log").read_text()
    assert not (box / "host" / "stub.log").exists()


def test_up_script_fail_closed_does_not_compose_or_stop(box: Path, sock: Path) -> None:
    home = ready_home(box)
    script = f'source "{UP}"\nhermes_docker_up_main\n'
    result = run(
        script,
        make_env(
            box,
            HOME=str(box / "user"),
            HERMES_HOME=str(home),
            HERMES_DOCKER_SOCK=str(sock),
            SYSTEMCTL_STATE="activating",
        ),
    )
    assert result.returncode != 0
    assert "activating" in result.stderr
    log = (box / "stub.log").read_text()
    assert "compose" not in log
    assert "stop" not in log
    assert "disable" not in log
    assert home.is_dir()
    assert (home / ".env").is_file()
    assert not (box / "opt-data").exists()


def test_up_script_missing_socket_and_missing_env(box: Path) -> None:
    home = ready_home(box)
    regular = box / "not-a-socket"
    regular.write_text("file\n")
    missing_sock = run(
        f'source "{UP}"\nhermes_docker_up_main\n',
        make_env(
            box / "sock",
            HOME=str(box / "sock" / "user"),
            HERMES_HOME=str(home),
            HERMES_DOCKER_SOCK=str(regular),
        ),
    )
    assert missing_sock.returncode != 0
    assert "not-a-socket" in missing_sock.stderr
    assert "compose" not in (box / "sock" / "stub.log").read_text()

    empty = box / "empty-home"
    empty.mkdir()
    missing_env = run(
        f'source "{UP}"\nhermes_docker_up_main\n',
        make_env(
            box / "env",
            HOME=str(box / "env" / "user"),
            HERMES_HOME=str(empty),
        ),
    )
    assert missing_env.returncode != 0
    assert "not seeding secrets" in missing_env.stderr
    assert not (empty / ".env").exists()
    assert empty.is_dir()


def test_up_script_refuses_foreign_and_parent_mounts(box: Path, sock: Path) -> None:
    home = ready_home(box)
    parent = str(home.parent)
    foreign = run(
        f'source "{UP}"\nhermes_docker_up_main\n',
        make_env(
            box / "foreign",
            HOME=str(box / "user"),
            HERMES_HOME=str(home),
            HERMES_DOCKER_SOCK=str(sock),
            DOCKER_PS_IDS="abc",
            DOCKER_INSPECT_NAME="/other",
            DOCKER_INSPECT_MOUNTS=f"{home} /opt/data",
        ),
    )
    assert foreign.returncode != 0
    assert "/other" in foreign.stderr
    assert "compose" not in (box / "foreign" / "stub.log").read_text()

    parent_mount = run(
        f'source "{UP}"\nhermes_docker_up_main\n',
        make_env(
            box / "parent",
            HOME=str(box / "user"),
            HERMES_HOME=str(home),
            HERMES_DOCKER_SOCK=str(sock),
            DOCKER_PS_IDS="abc",
            DOCKER_INSPECT_NAME="/parent",
            DOCKER_INSPECT_MOUNTS=f"{parent} /host",
        ),
    )
    assert parent_mount.returncode != 0
    assert "/parent" in parent_mount.stderr
    assert "compose" not in (box / "parent" / "stub.log").read_text()


def test_up_script_docker_ps_failure_and_host_process(box: Path, sock: Path) -> None:
    home = ready_home(box)
    ps_fail = run(
        f'source "{UP}"\nhermes_docker_up_main\n',
        make_env(
            box / "ps",
            HOME=str(box / "user"),
            HERMES_HOME=str(home),
            HERMES_DOCKER_SOCK=str(sock),
            DOCKER_PS_RC="1",
        ),
    )
    assert ps_fail.returncode != 0
    assert "docker ps failed" in ps_fail.stderr
    assert "compose" not in (box / "ps" / "stub.log").read_text()

    host_proc = run(
        f'source "{UP}"\nhermes_docker_up_main\n',
        make_env(
            box / "proc",
            HOME=str(box / "user"),
            HERMES_HOME=str(home),
            HERMES_DOCKER_SOCK=str(sock),
            PS_LINES="nohup hermes gateway",
        ),
    )
    assert host_proc.returncode != 0
    assert "host hermes gateway process" in host_proc.stderr
    assert "compose" not in (box / "proc" / "stub.log").read_text()
    assert "disable" not in (box / "proc" / "stub.log").read_text()


def test_up_script_success_disables_unit_and_does_not_down_v(box: Path, sock: Path) -> None:
    home = ready_home(box)
    result = run(
        f'source "{UP}"\nhermes_docker_up_main\n',
        make_env(
            box,
            HOME=str(box / "user"),
            HERMES_HOME=str(home),
            HERMES_DOCKER_SOCK=str(sock),
            DOCKER_RUNNING="true",
            DOCKER_IMAGE="nousresearch/hermes-agent:latest",
            DOCKER_CMD="gateway run",
            SYSTEMCTL_STATE="inactive",
            SYSTEMCTL_ENABLED="not-found",
            DOCKER_PS_IDS="self",
            DOCKER_INSPECT_NAME="/hermes",
            DOCKER_INSPECT_MOUNTS=f"{home} /opt/data",
        ),
    )
    assert result.returncode == 0, result.stderr
    assert "hermes gateway status" not in result.stdout
    assert "gateway container hermes is up" in result.stdout
    log = (box / "stub.log").read_text()
    assert "up -d --force-recreate --no-deps --pull never" in log
    assert "--pull always" not in log
    assert "down" not in log
    assert " -v" not in log
    assert " disable " in f" {log} " or "disable" in log
    assert "stop" not in log
    link = box / "opt-data"
    assert link.is_symlink()
    assert os.path.realpath(link) == str(home.resolve())
    assert not (box / "hermes.log").exists()


def test_health_two_writers_and_unrelated_container(box: Path) -> None:
    official = {
        "DOCKER_RUNNING": "true",
        "DOCKER_IMAGE": "nousresearch/hermes-agent",
        "DOCKER_CMD": "gateway run",
    }
    both = run(
        source_lib("apply_gateway_health\n"),
        make_env(box / "both", SYSTEMCTL_STATE="activating", **official),
    )
    assert both.returncode != 0
    assert "two gateway writers" in both.stderr
    assert "OK  gateway container" not in both.stdout
    assert not (box / "both" / "hermes.log").exists()

    query = run(
        source_lib("apply_gateway_health\n"),
        make_env(box / "query", SYSTEMCTL_RC="1", **official),
    )
    assert query.returncode != 0
    assert "cannot be queried" in query.stderr

    alone = run(
        source_lib("apply_gateway_health\n"),
        make_env(
            box / "alone",
            SYSTEMCTL_STATE="inactive",
            PS_LINES="bash unit-test",
            **official,
        ),
    )
    assert alone.returncode == 0, alone.stderr
    assert "OK  gateway container hermes (nousresearch/hermes-agent gateway run)" in alone.stdout
    assert "gateway status" not in alone.stdout
    assert not (box / "alone" / "hermes.log").exists()

    unrelated = run(
        source_lib("apply_gateway_health\n"),
        make_env(
            box / "other",
            DOCKER_RUNNING="true",
            DOCKER_IMAGE="busybox",
            DOCKER_CMD="sleep infinity",
            HERMES_RC="1",
        ),
    )
    assert unrelated.returncode != 0
    assert "OK  gateway container" not in unrelated.stdout
    assert "gateway status" in (box / "other" / "hermes.log").read_text()


def test_update_script_docker_path_does_not_call_hermes_update(box: Path, sock: Path) -> None:
    home = ready_home(box)
    env = make_env(
        box,
        HOME=str(box / "user"),
        HERMES_HOME=str(home),
        HERMES_DOCKER_RUNTIME="1",
        HERMES_DOCKER_SOCK=str(sock),
        DOCKER_RUNNING="true",
        DOCKER_IMAGE="nousresearch/hermes-agent",
        DOCKER_CMD="gateway run",
        SYSTEMCTL_ENABLED="disabled",
    )
    bindir = Path(env["PATH"].split(os.pathsep)[0])
    (bindir / "hermes").unlink()
    local_bin = Path(env["HOME"]) / ".local" / "bin"
    local_bin.mkdir(parents=True)
    for name in ("docker", "systemctl", "stat", "ps", "pgrep"):
        shutil.copy(bindir / name, local_bin / name)
        (local_bin / name).chmod(0o755)
    env["PATH"] = str(bindir) + os.pathsep + "/usr/bin:/bin:/usr/sbin"
    result = run(f'bash "{UPDATE}"\n', env)
    assert result.returncode == 0, result.stderr
    log = (box / "stub.log").read_text()
    assert "pull" in log
    assert "up -d --force-recreate --no-deps --pull never" in log
    assert "down" not in log
    assert "--pull always" not in log
    assert "Running hermes update" not in result.stdout
    assert "not hermes update" in result.stdout


def test_child_mount_is_not_a_second_writer(box: Path, sock: Path) -> None:
    home = ready_home(box)
    child = home / "memories"
    assert run(
        source_lib(f'mount_covers_data "{child}" "{home}" && echo cover || echo clear\n'),
        make_env(box / "fn", HOME=str(box / "user")),
    ).stdout.strip().endswith("clear")
    result = run(
        f'source "{UP}"\nhermes_docker_up_main\n',
        make_env(
            box,
            HOME=str(box / "user"),
            HERMES_HOME=str(home),
            HERMES_DOCKER_SOCK=str(sock),
            DOCKER_RUNNING="true",
            DOCKER_IMAGE="nousresearch/hermes-agent",
            DOCKER_CMD="gateway run",
            DOCKER_PS_IDS="sandbox",
            DOCKER_INSPECT_NAME="/sandbox",
            DOCKER_INSPECT_MOUNTS=f"{child} /memories",
            SYSTEMCTL_ENABLED="disabled",
        ),
    )
    assert result.returncode == 0, result.stderr
    assert "second writer" not in result.stderr
    assert "compose" in (box / "stub.log").read_text()


def test_recreate_pulls_only_when_image_absent(box: Path) -> None:
    script = source_lib(f'recreate_hermes_container "{COMPOSE}"\n')
    result = run(script, make_env(box, DOCKER_IMAGE_INSPECT_RC="1"))
    assert result.returncode == 0, result.stderr
    log = (box / "stub.log").read_text()
    assert "pull nousresearch/hermes-agent" in log
    assert "--pull never" in log
    assert "--pull always" not in log


def test_docker_io_image_prefix_counts_as_official(box: Path) -> None:
    result = run(
        source_lib("apply_gateway_health\n"),
        make_env(
            box,
            DOCKER_RUNNING="true",
            DOCKER_IMAGE="docker.io/nousresearch/hermes-agent:latest",
            DOCKER_CMD="gateway run",
            SYSTEMCTL_STATE="inactive",
        ),
    )
    assert result.returncode == 0, result.stderr
    assert "OK  gateway container hermes" in result.stdout


def test_disable_failure_stops_container_without_rm_v(box: Path, sock: Path) -> None:
    home = ready_home(box)
    result = run(
        f'source "{UP}"\nhermes_docker_up_main\n',
        make_env(
            box,
            HOME=str(box / "user"),
            HERMES_HOME=str(home),
            HERMES_DOCKER_SOCK=str(sock),
            DOCKER_RUNNING="true",
            DOCKER_IMAGE="nousresearch/hermes-agent",
            DOCKER_CMD="gateway run",
            SYSTEMCTL_STATE="inactive",
            SYSTEMCTL_ENABLED="enabled",
        ),
    )
    assert result.returncode != 0
    assert "still enabled" in result.stderr
    log = (box / "stub.log").read_text()
    assert "stop hermes" in log
    assert not any(line == "rm" or line.startswith("rm ") for line in log.splitlines())
    assert "down" not in log
    assert not (box / "opt-data").exists()


def test_disable_when_unit_stays_enabled(box: Path) -> None:
    result = run(
        source_lib("disable_host_gateway_unit\n"),
        make_env(box, SYSTEMCTL_STATE="inactive", SYSTEMCTL_ENABLED="enabled"),
    )
    assert result.returncode != 0
    assert "still enabled" in result.stderr
    assert "stop" not in (box / "stub.log").read_text()


def test_symlink_sudo_when_parent_not_writable(box: Path) -> None:
    home = ready_home(box)
    locked = box / "locked"
    locked.mkdir()
    locked.chmod(0o500)
    link = locked / "opt-data"
    env = make_env(box, HOME=str(box / "user"))
    sudo = Path(env["PATH"].split(os.pathsep)[0]) / "sudo"
    sudo.write_text(
        "#!/bin/sh\n"
        'echo "$*" >> "$STUB_LOG"\n'
        '[ "$1" = "-n" ] || exit 1\n'
        "shift\n"
        'dest=""; for arg in "$@"; do dest="$arg"; done\n'
        'chmod u+w "$(dirname "$dest")"\n'
        '"$@"\n'
    )
    sudo.chmod(0o755)
    result = run(
        source_lib(f'ensure_opt_data_symlink "{home}" "{link}"\n'),
        env,
    )
    assert result.returncode == 0, result.stderr
    assert "-n ln -s" in (box / "stub.log").read_text()
    assert link.is_symlink()
    locked.chmod(0o700)


def test_refresh_gateway_flag_arms(box: Path, sock: Path) -> None:
    home = ready_home(box)
    host = run(
        source_lib("refresh_gateway\n"),
        make_env(box / "host", HOME=str(box / "user")),
    )
    assert host.returncode == 0, host.stderr
    host_hermes = (box / "host" / "hermes.log").read_text()
    assert "gateway restart" in host_hermes
    assert "gateway status" in host_hermes
    assert not (box / "host" / "stub.log").exists() or "compose" not in (
        box / "host" / "stub.log"
    ).read_text()

    opted = run(
        source_lib("refresh_gateway\n"),
        make_env(
            box / "on",
            HOME=str(box / "user"),
            HERMES_HOME=str(home),
            HERMES_DOCKER_RUNTIME="1",
            HERMES_DOCKER_SOCK=str(sock),
            HERMES_OPT_DATA_LINK=str(box / "on" / "opt-data"),
            DOCKER_RUNNING="true",
            DOCKER_IMAGE="nousresearch/hermes-agent",
            DOCKER_CMD="gateway run",
            SYSTEMCTL_ENABLED="disabled",
        ),
    )
    assert opted.returncode == 0, opted.stderr
    assert "compose" in (box / "on" / "stub.log").read_text()
    assert not (box / "on" / "hermes.log").exists()


def test_deploy_flag_arms_call_stub_ssh(box: Path) -> None:
    script = source_lib(
        """
ssh_cmd() { printf '%s\\n' "$*" >> "$SSH_LOG"; }
export -f ssh_cmd
gateway_refresh_ssh /remote "start_host_gateway"
"""
    )
    off = run(script, make_env(box / "off", SSH_LOG=str(box / "off" / "ssh.log")))
    assert off.returncode == 0, off.stderr
    off_log = (box / "off" / "ssh.log").read_text()
    assert "start_host_gateway" in off_log
    assert "hermes-docker-up.sh" not in off_log

    on = run(
        script,
        make_env(
            box / "on",
            HERMES_DOCKER_RUNTIME="1",
            SSH_LOG=str(box / "on" / "ssh.log"),
        ),
    )
    assert on.returncode == 0, on.stderr
    on_log = (box / "on" / "ssh.log").read_text()
    assert on_log.startswith("HERMES_DOCKER_RUNTIME=1 ")
    assert "hermes-docker-up.sh" in on_log
    assert "start_host_gateway" not in on_log


def test_health_host_process_beside_container_and_stopped_container(box: Path) -> None:
    official = {
        "DOCKER_RUNNING": "true",
        "DOCKER_IMAGE": "nousresearch/hermes-agent",
        "DOCKER_CMD": "gateway run",
        "SYSTEMCTL_STATE": "inactive",
        "PS_LINES": "nohup hermes gateway",
    }
    both = run(source_lib("apply_gateway_health\n"), make_env(box / "both", **official))
    assert both.returncode != 0
    assert "two gateway writers" in both.stderr
    assert "OK  gateway container" not in both.stdout
    assert not (box / "both" / "hermes.log").exists()

    stopped = run(
        source_lib("apply_gateway_health\n"),
        make_env(
            box / "stopped",
            DOCKER_RUNNING="false",
            DOCKER_IMAGE="nousresearch/hermes-agent",
            DOCKER_CMD="gateway run",
            HERMES_RC="1",
        ),
    )
    assert stopped.returncode != 0
    assert "OK  gateway container" not in stopped.stdout
    assert "gateway status" in (box / "stopped" / "hermes.log").read_text()


@pytest.mark.parametrize("script", ["firecrawl-up.sh", "agent-reach-up.sh", "notion-up.sh", "mnemosyne-up.sh"])
def test_no_host_hermes_writes_after_refresh(script: str) -> None:
    # The up script reclaims root-owned files once, at start. Root SSH runs after
    # it leave files the container user cannot write (mnemosyne.db, cron, backups).
    text = (ROOT / "scripts" / "remote" / script).read_text()
    tail = text[text.rindex("refresh_gateway") :]
    for marker in ("hermes ", "$VENV/bin/", "pin-cron-models.sh"):
        assert marker not in tail, f"{script} runs {marker!r} after refresh_gateway"


def test_run_mnemosyne_uses_container_as_owner_with_runtime_env(box: Path) -> None:
    home = box / "home"
    home.mkdir()
    venv_bin = home / ".mnemosyne" / "venv" / "bin"
    venv_bin.mkdir(parents=True)
    write_exe(venv_bin / "mnemosyne", '#!/bin/sh\necho "host $*" >> "$STUB_LOG"\n')
    body = 'run_mnemosyne store x\n'

    up = run(source_lib(body), make_env(box / "up", HERMES_HOME=str(home), DOCKER_RUNNING="true",
                                        STAT_UID="999", STAT_GID="976"))
    assert up.returncode == 0, up.stderr
    log = (box / "up" / "stub.log").read_text()
    assert f"exec -u 999:976 --env-file {home}/.env hermes /opt/data/.mnemosyne/venv/bin/mnemosyne store x" in log
    assert "host store" not in log

    down = run(source_lib(body), make_env(box / "down", HERMES_HOME=str(home), DOCKER_RUNNING="false"))
    assert down.returncode == 0, down.stderr
    log = (box / "down" / "stub.log").read_text()
    assert "host store x" in log
    assert "exec -u" not in log
