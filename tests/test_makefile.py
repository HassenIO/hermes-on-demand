"""Makefile contract: phony help targets, and who may call deploy.sh bare."""

from __future__ import annotations

import os
import pty
import re
import shutil
import stat
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET_RE = re.compile(r"^([A-Za-z0-9_-]+)\s*:(?!=)(.*)$")
INVOKE_RE = re.compile(r"\$\(DEPLOY\)|(?:\./)?scripts/deploy\.sh")


def logical_lines(text: str) -> list[str]:
    out: list[str] = []
    buf = ""
    pending = False
    for line in text.splitlines():
        buf = buf + line if pending else line
        if buf.endswith("\\"):
            buf = buf[:-1] + " "
            pending = True
            continue
        out.append(buf)
        buf = ""
        pending = False
    if pending and buf:
        out.append(buf)
    return out


def parse_makefile(text: str) -> tuple[set[str], dict[str, tuple[str, str, str]]]:
    lines = logical_lines(text)
    phony: set[str] = set()
    targets: dict[str, tuple[str, str, str]] = {}
    index = 0
    while index < len(lines):
        line = lines[index]
        if line.startswith(".PHONY:"):
            phony.update(line.split(":", 1)[1].split())
            index += 1
            continue
        match = TARGET_RE.match(line)
        if match and not line.startswith("\t"):
            name = match.group(1)
            rest = match.group(2)
            prereqs, _, comment = rest.partition("##")
            recipe: list[str] = []
            index += 1
            while index < len(lines) and lines[index].startswith("\t"):
                recipe.append(lines[index])
                index += 1
            targets[name] = (comment.strip(), "\n".join(recipe), prereqs.strip())
            continue
        index += 1
    return phony, targets


def flagless_invokers(targets: dict[str, tuple[str, str, str]]) -> set[str]:
    found = set()
    for name, (_comment, recipe, _prereqs) in targets.items():
        for line in recipe.splitlines():
            if not INVOKE_RE.search(line):
                continue
            if "--" not in line:
                found.add(name)
    return found


def test_every_target_is_phony_and_documented() -> None:
    text = (ROOT / "Makefile").read_text()
    phony, targets = parse_makefile(text)
    assert targets
    assert set(targets) == phony
    for name, (comment, _recipe, _prereqs) in targets.items():
        assert comment, name


def test_only_deploy_and_full_invoke_deploy_without_a_mode() -> None:
    text = (ROOT / "Makefile").read_text()
    _phony, targets = parse_makefile(text)
    bare = flagless_invokers(targets)
    assert "deploy" in bare
    assert bare <= {"deploy", "full"}
    for name, (_comment, recipe, _prereqs) in targets.items():
        if name in {"deploy", "full"}:
            continue
        for line in recipe.splitlines():
            if INVOKE_RE.search(line):
                assert "--" in line, line


def test_lint_target_is_bash_n_only() -> None:
    text = (ROOT / "Makefile").read_text()
    _phony, targets = parse_makefile(text)
    _comment, recipe, prereqs = targets["lint"]
    assert prereqs == ""
    assert "bash -n" in recipe
    assert "ssh" not in recipe
    assert "uv " not in recipe


def test_install_hooks_sets_hooks_path_only() -> None:
    text = (ROOT / "Makefile").read_text()
    _phony, targets = parse_makefile(text)
    _comment, recipe, prereqs = targets["install-hooks"]
    assert prereqs == ""
    assert "core.hooksPath .githooks" in recipe
    assert "deploy" not in recipe
    assert "ssh" not in recipe
    assert "source" not in recipe
    hook = (ROOT / ".githooks" / "pre-commit").read_text()
    script = (ROOT / "scripts" / "pre-commit.sh").read_text()
    assert "scripts/pre-commit.sh" in hook
    assert "make lint" in script
    assert "make test" in script
    assert "ssh" not in script
    assert ".env" not in script


def test_test_target_does_not_ssh_or_load_env() -> None:
    text = (ROOT / "Makefile").read_text()
    _phony, targets = parse_makefile(text)
    comment, recipe, prereqs = targets["test"]
    assert comment
    assert prereqs == ""
    assert "ssh" not in recipe
    assert "uv run --no-env-file pytest" in recipe
    assert "source" not in recipe
    assert ".env" not in recipe.replace("--no-env-file", "")


def test_logs_streams_gateway_journal_over_batch_ssh() -> None:
    text = (ROOT / "Makefile").read_text()
    _phony, targets = parse_makefile(text)
    comment, recipe, prereqs = targets["logs"]
    assert comment
    assert prereqs == "check-env"
    assert "BatchMode=yes" in recipe
    assert "StrictHostKeyChecking=accept-new" in recipe
    assert "'journalctl --user -u hermes-gateway -f'" in recipe
    assert not INVOKE_RE.search(recipe)
    _c, help_recipe, _p = targets["help"]
    most_used = help_recipe.split("Most used:", 1)[1].split("Setup extensions:", 1)[0]
    assert "make logs" in most_used


def run_logs(
    workdir: Path, env_text: str, stdin: int = subprocess.DEVNULL
) -> tuple[subprocess.CompletedProcess[str], Path]:
    shutil.copy(ROOT / "Makefile", workdir / "Makefile")
    (workdir / ".env").write_text(env_text)
    bindir = workdir / "bin"
    bindir.mkdir()
    argv_file = workdir / "argv"
    stub = bindir / "ssh"
    stub.write_text(f"#!/bin/sh\nprintf '%s\\n' \"$@\" > '{argv_file}'\n")
    stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
    env = {
        "PATH": str(bindir) + os.pathsep + os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": str(workdir),
    }
    result = subprocess.run(
        ["make", "-s", "-C", str(workdir), "logs"],
        env=env,
        stdin=stdin,
        capture_output=True,
        text=True,
    )
    return result, argv_file


def test_logs_passes_env_target_to_ssh(tmp_path: Path) -> None:
    result, argv_file = run_logs(
        tmp_path,
        "TARGET_HOST=vps.example.invalid\n"
        "TARGET_USER=hermes\n"
        "SSH_PORT=2222\n"
        "SSH_IDENTITY_FILE=/keys/id_test\n",
    )
    assert result.returncode == 0, result.stderr
    assert argv_file.read_text().splitlines() == [
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=accept-new",
        "-p",
        "2222",
        "-i",
        "/keys/id_test",
        "hermes@vps.example.invalid",
        "journalctl --user -u hermes-gateway -f",
    ]


def test_logs_defaults_port_and_skips_identity(tmp_path: Path) -> None:
    result, argv_file = run_logs(
        tmp_path, "TARGET_HOST=vps.example.invalid\nTARGET_USER=hermes\n"
    )
    assert result.returncode == 0, result.stderr
    args = argv_file.read_text().splitlines()
    assert args[args.index("-p") + 1] == "22"
    assert "-i" not in args
    assert "-t" not in args


def test_logs_allocates_remote_tty_for_terminal_stdin(tmp_path: Path) -> None:
    primary, secondary = pty.openpty()
    try:
        result, argv_file = run_logs(
            tmp_path,
            "TARGET_HOST=vps.example.invalid\nTARGET_USER=hermes\n",
            stdin=secondary,
        )
    finally:
        os.close(secondary)
        os.close(primary)
    assert result.returncode == 0, result.stderr
    args = argv_file.read_text().splitlines()
    assert "-t" in args
    assert args.index("-t") < args.index("hermes@vps.example.invalid")


def test_logs_requires_target_host(tmp_path: Path) -> None:
    result, argv_file = run_logs(tmp_path, "TARGET_USER=hermes\n")
    assert result.returncode != 0
    assert "TARGET_HOST missing in .env" in result.stderr
    assert not argv_file.exists()
