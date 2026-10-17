"""Assert config/config.yaml.example. Does not execute a deploy."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "config" / "config.yaml.example"

SECRET_PATTERNS = (
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"\bsk-[A-Za-z0-9]{8,}"),
    re.compile(r"\bntn_[A-Za-z0-9]{8,}"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"\b\d{8,10}:[A-Za-z0-9_-]{30,}\b"),
    re.compile(r"\bghp_[A-Za-z0-9]{20,}"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}"),
    re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}"),
)
ASSIGNMENT = re.compile(
    r"(?i)\b(api[_-]?key|secret|password|access[_-]?key|bot[_-]?token)\s*:\s*['\"]?[A-Za-z0-9_-]{8,}"
)


def active_lines(text: str) -> list[str]:
    lines = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        lines.append(line)
    return lines


def find_key(lines: list[str], key: str) -> int:
    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith(f"{key}:"):
            return index
    raise AssertionError(f"missing {key}")


def body_after(lines: list[str], index: int) -> list[str]:
    base = len(lines[index]) - len(lines[index].lstrip())
    body = []
    for line in lines[index + 1 :]:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        if indent <= base:
            break
        body.append(line)
    return body


def raw_scalar(lines: list[str], key: str) -> str:
    index = find_key(lines, key)
    return lines[index].strip()[len(key) + 1 :].strip()


def list_items(lines: list[str], key: str) -> list[str]:
    body = body_after(lines, find_key(lines, key))
    items = []
    for line in body:
        stripped = line.strip()
        if not stripped.startswith("- "):
            break
        items.append(stripped[2:].strip().strip('"').strip("'"))
    return items


def test_config_invariants() -> None:
    text = CONFIG.read_text()
    lines = active_lines(text)

    memory = body_after(lines, find_key(lines, "memory"))
    assert raw_scalar(memory, "memory_enabled") == "false"
    assert raw_scalar(memory, "user_profile_enabled") == "false"

    terminal = body_after(lines, find_key(lines, "terminal"))
    forwarded = list_items(terminal, "docker_forward_env")
    assert forwarded
    assert not any(item.startswith("AWS_") or "AWS_" in item for item in forwarded)

    web = body_after(lines, find_key(lines, "web"))
    assert raw_scalar(web, "search_backend") == "searxng"
    assert raw_scalar(web, "extract_backend") == "firecrawl"

    model = body_after(lines, find_key(lines, "model"))
    assert raw_scalar(model, "default")

    assert "LLM_MODEL" not in text

    for pattern in SECRET_PATTERNS:
        assert pattern.search(text) is None, pattern.pattern
    for line in lines:
        assert ASSIGNMENT.search(line) is None, line
