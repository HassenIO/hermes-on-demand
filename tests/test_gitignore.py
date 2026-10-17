"""git check-ignore matches runtime copies and not README.md."""

from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def ignored(path: str) -> bool:
    result = subprocess.run(
        ["git", "check-ignore", "-q", "--", path],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert result.returncode in (0, 1)
    return result.returncode == 0


def test_runtime_copies_and_env_are_ignored() -> None:
    assert ignored(".env")
    assert ignored("skills/nope/SKILL.md")
    assert ignored("cron/nope.json")
    assert ignored("cron/jobs.json")
    assert ignored("artifacts/USER.md")
    assert ignored("artifacts/nope.md")


def test_readme_in_those_trees_is_not_ignored() -> None:
    for path in (
        "skills/README.md",
        "skills/nope/README.md",
        "skills/foo/bar/README.md",
        "cron/README.md",
        "cron/nested/README.md",
        "artifacts/README.md",
        "artifacts/nested/README.md",
    ):
        assert not ignored(path), path
