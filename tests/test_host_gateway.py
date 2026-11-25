"""Host gateway runtime. Stub binaries only: no SSH, no Docker daemon, no systemd."""

from __future__ import annotations

import os
import stat
import subprocess
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMMON = ROOT / "scripts" / "lib" / "common.sh"
REMOTE = ROOT / "scripts" / "remote"

# `docker inspect hermes` answers from DOCKER_RUNNING: unset = no container.
DOCKER_STUB = """#!/bin/sh
echo "docker $*" >> "$STUB_LOG"
if [ "$1" = "inspect" ]; then
  [ -n "${DOCKER_RUNNING+x}" ] || exit 1
  case "$*" in
    *State.Running*) echo "$DOCKER_RUNNING" ;;
  esac
  exit 0
fi
exit 0
"""

HERMES_STUB = """#!/bin/sh
echo "hermes $*" >> "$STUB_LOG"
if [ "$1" = "--print-runtime-command" ]; then
  [ -n "${RUNTIME_PY:-}" ] || exit 1
  printf '["%s", "-I", "-c", "pass"]\\n' "$RUNTIME_PY"
fi
exit 0
"""


def write_exe(path: Path, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(body))
    path.chmod(path.stat().st_mode | stat.S_IEXEC)


def make_env(tmp: Path, **extra: str) -> dict[str, str]:
    bindir = tmp / "bin"
    write_exe(bindir / "docker", DOCKER_STUB)
    write_exe(bindir / "hermes", HERMES_STUB)
    home = tmp / "user"
    home.mkdir(parents=True, exist_ok=True)
    env = {
        "PATH": str(bindir) + os.pathsep + os.environ.get("PATH", ""),
        "HOME": str(home),
        "STUB_LOG": str(tmp / "stub.log"),
    }
    env.update(extra)
    return env


def run_common(body: str, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    script = f'set -euo pipefail\nsource "{COMMON}"\n{body}\n'
    return subprocess.run(["bash", "-c", script], cwd=ROOT, env=env, capture_output=True, text=True)


def stub_log(tmp: Path) -> str:
    log = tmp / "stub.log"
    return log.read_text() if log.exists() else ""


def test_host_start_refuses_running_container(tmp_path: Path) -> None:
    result = run_common("start_host_gateway\necho should-not-run", make_env(tmp_path, DOCKER_RUNNING="true"))
    assert result.returncode != 0
    assert "container hermes is running" in result.stderr
    assert "should-not-run" not in result.stdout
    assert "hermes gateway" not in stub_log(tmp_path)


def test_host_start_refuses_stopped_container(tmp_path: Path) -> None:
    result = run_common("start_host_gateway\necho should-not-run", make_env(tmp_path, DOCKER_RUNNING="false"))
    assert result.returncode != 0
    assert "container hermes exists" in result.stderr
    assert "hermes gateway" not in stub_log(tmp_path)


def test_host_start_and_refresh_restart_the_unit(tmp_path: Path) -> None:
    result = run_common("refresh_gateway", make_env(tmp_path))
    assert result.returncode == 0, result.stderr
    log = stub_log(tmp_path)
    assert "hermes gateway restart" in log
    assert "hermes gateway status" in log


def test_runtime_python_from_launcher_then_venv_fallback(tmp_path: Path) -> None:
    py = tmp_path / "tools" / "python3"
    write_exe(py, "#!/bin/sh\nexit 0\n")
    result = run_common("hermes_runtime_python", make_env(tmp_path, RUNTIME_PY=str(py)))
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == str(py)

    venv_py = tmp_path / "user" / ".hermes" / "hermes-agent" / "venv" / "bin" / "python"
    write_exe(venv_py, "#!/bin/sh\nexit 0\n")
    result = run_common("hermes_runtime_python", make_env(tmp_path))
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == str(venv_py)

    venv_py.unlink()
    result = run_common("hermes_runtime_python", make_env(tmp_path))
    assert result.returncode != 0


def test_run_mnemosyne_sees_runtime_env_without_leaking_it(tmp_path: Path) -> None:
    hermes_home = tmp_path / "user" / ".hermes"
    write_exe(
        hermes_home / ".mnemosyne" / "venv" / "bin" / "mnemosyne",
        '#!/bin/sh\necho "args=$* model=$MNEMOSYNE_EMBEDDING_MODEL"\n',
    )
    (hermes_home / ".env").write_text('MNEMOSYNE_EMBEDDING_MODEL="openai/text-embedding-3-small"\n')
    body = 'run_mnemosyne store hello\necho "caller=${MNEMOSYNE_EMBEDDING_MODEL:-unset}"'
    result = run_common(body, make_env(tmp_path))
    assert result.returncode == 0, result.stderr
    assert "args=store hello model=openai/text-embedding-3-small" in result.stdout
    assert "caller=unset" in result.stdout


def test_docker_gateway_runtime_is_gone() -> None:
    assert not (ROOT / "scripts" / "lib" / "hermes-docker.sh").exists()
    assert not (REMOTE / "hermes-docker-up.sh").exists()
    assert not (ROOT / "docker" / "hermes").exists()
    stale = ("run_in_gateway", "docker_runtime_requested", "with_docker_runtime_flag",
             "gateway_refresh_ssh", "lib/hermes-docker.sh", "hermes-docker-up.sh", "docker/hermes", "/opt/data", "/opt/hermes")
    paths = [ROOT / "Makefile", *sorted((ROOT / "scripts").rglob("*.sh"))]
    for path in paths:
        text = path.read_text()
        for marker in stale:
            assert marker not in text, f"{path.relative_to(ROOT)} still has {marker!r}"
    # The only mention left is deploy's warning that a stale flag is ignored.
    for path in paths:
        if "HERMES_DOCKER_RUNTIME" in path.read_text():
            assert path.name == "deploy.sh", path
    deploy = (ROOT / "scripts" / "deploy.sh").read_text()
    assert "HERMES_DOCKER_RUNTIME is no longer supported" in deploy


def test_bootstrap_installs_unit_with_linger_and_one_writer() -> None:
    text = (REMOTE / "bootstrap.sh").read_text()
    guard = text.index("if hermes_container_present; then")
    install = text.index("hermes gateway install")
    assert guard < install < text.index("enable-linger") < text.index("start_host_gateway")


def test_health_requires_unit_and_refuses_leftover_container() -> None:
    text = (REMOTE / "healthcheck.sh").read_text()
    assert "systemctl --user is-active --quiet hermes-gateway" in text
    # `hermes gateway status` exits 0 for a stopped service: it must never pass health.
    assert "elif hermes gateway status" not in text
    unit = text[text.index("if systemctl --user is-active --quiet hermes-gateway") :]
    assert "failed=1" in unit[unit.index("\nelse\n") : unit.index("\nfi\n")]
    block = text[text.index("if hermes_container_present; then") :]
    assert "failed=1" in block[: block.index("fi\n")]
    # set -o pipefail: grep -q closing the pipe early fails it with SIGPIPE (141).
    for line in text.splitlines():
        assert not ("hermes " in line and "| grep -q" in line), line


def test_mnemosyne_venv_comes_from_hermes_python_and_rebuilds_when_broken() -> None:
    text = (REMOTE / "mnemosyne-up.sh").read_text()
    assert 'HERMES_PYTHON="$(hermes_runtime_python)"' in text
    assert "if ! venv_usable; then" in text
    assert '"$HERMES_PYTHON" -m venv --clear "$VENV"' in text


def run_venv_usable(venv: Path) -> int:
    text = (REMOTE / "mnemosyne-up.sh").read_text()
    fn = text[text.index("venv_usable() {") : text.index("\n}\n", text.index("venv_usable() {")) + 3]
    script = f'set -euo pipefail\nVENV="{venv}"\n{fn}\nvenv_usable'
    return subprocess.run(["bash", "-c", script], capture_output=True, text=True).returncode


def test_mnemosyne_venv_with_stale_entry_point_is_not_usable(tmp_path: Path) -> None:
    venv = tmp_path / "venv"
    write_exe(venv / "bin" / "python", "#!/bin/sh\nexit 0\n")
    assert run_venv_usable(venv) == 0  # fresh venv, no entry points yet
    write_exe(venv / "bin" / "mnemosyne-hermes", f"#!{venv}/bin/python\nimport x\n")
    assert run_venv_usable(venv) == 0
    # Built in the old container: shebang names an interpreter that no longer exists.
    write_exe(venv / "bin" / "mnemosyne", "#!/opt/data/.mnemosyne/venv/bin/python\nimport x\n")
    assert run_venv_usable(venv) != 0
    (venv / "bin" / "mnemosyne").unlink()
    write_exe(venv / "bin" / "python", "#!/bin/sh\nexit 1\n")  # Python that cannot start
    assert run_venv_usable(venv) != 0


def test_agent_reach_prunes_build_leftovers_after_smoke() -> None:
    text = (REMOTE / "agent-reach-up.sh").read_text()
    smoke = text.index('|| die "image tool smoke failed"')
    assert smoke < text.index("docker image prune -f") < text.index("docker builder prune -af")
    assert "docker system prune" not in text and "image prune -a" not in text


def test_config_push_pins_before_restart() -> None:
    text = (ROOT / "scripts" / "deploy.sh").read_text()
    block = text[text.index('if [[ "$MODE" == "config-only" ]]') :]
    block = block[: block.index("\n  exit 0\nfi")]
    assert block.index("pin-cron-models.sh") < block.index("start_host_gateway")
    assert block.count("pin-cron-models.sh") == 1


def test_notion_up_never_logs_page_ids() -> None:
    for line in (REMOTE / "notion-up.sh").read_text().splitlines():
        if line.strip().startswith(("log ", "warn ")):
            assert "PARENT_NORM" not in line and "_DB}" not in line and "TMPL}" not in line, line
