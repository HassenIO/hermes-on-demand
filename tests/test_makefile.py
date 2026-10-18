"""Makefile contract: phony help targets, and who may call deploy.sh bare."""

from __future__ import annotations

import re
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
