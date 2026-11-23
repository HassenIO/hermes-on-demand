"""Three-way artifact decision in scripts/lib/artifacts-sync.sh. No SSH."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "scripts" / "lib" / "artifacts-sync.sh"


def bash(script: str, *args: str) -> subprocess.CompletedProcess[str]:
    env = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": os.environ.get("HOME", "/tmp"),
    }
    return subprocess.run(
        ["bash", "-c", f"set -euo pipefail; source scripts/lib/common.sh; source '{LIB}'; {script}", "_", *args],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
    )


def sync(tmp: Path, base: str | None, local: str | None, remote: str | None) -> tuple[str, str | None]:
    paths = {}
    for name, text in (("base", base), ("local", local), ("remote", remote)):
        path = tmp / name
        if text is not None:
            path.write_text(text)
        paths[name] = path
    result = bash('artifact_sync_one "$1" "$2" "$3"', str(paths["base"]), str(paths["local"]), str(paths["remote"]))
    assert result.returncode == 0, result.stderr
    out = paths["local"].read_text() if paths["local"].exists() else None
    return result.stdout.strip(), out


def test_same_when_local_matches_remote(tmp_path: Path) -> None:
    assert sync(tmp_path, "a\n", "b\n", "b\n") == ("same", "b\n")


def test_same_ignores_line_endings_and_trailing_blank_lines(tmp_path: Path) -> None:
    assert sync(tmp_path, None, "a\r\nb\r\n\r\n", "a\nb\n")[0] == "same"


def test_pull_when_only_remote_changed(tmp_path: Path) -> None:
    assert sync(tmp_path, "a\n", "a\n", "a\nhermes\n") == ("pull", "a\nhermes\n")


def test_push_when_only_local_changed(tmp_path: Path) -> None:
    assert sync(tmp_path, "a\n", "a\nmine\n", "a\n") == ("push", "a\nmine\n")


def test_clean_merge_keeps_both_sides(tmp_path: Path) -> None:
    base = "one\n\ntwo\n\nthree\n"
    local = "ONE\n\ntwo\n\nthree\n"
    remote = "one\n\ntwo\n\nthree\n\nfour\n"
    assert sync(tmp_path, base, local, remote) == ("merged", "ONE\n\ntwo\n\nthree\n\nfour\n")


def test_conflict_leaves_git_markers(tmp_path: Path) -> None:
    status, out = sync(tmp_path, "a\n", "mine\n", "theirs\n")
    assert status == "conflict"
    assert out is not None
    assert "<<<<<<< local" in out
    assert ">>>>>>> remote" in out
    assert "mine" in out and "theirs" in out


def test_missing_base_and_different_sides_conflicts(tmp_path: Path) -> None:
    assert sync(tmp_path, None, "mine\n", "theirs\n")[0] == "conflict"


def test_missing_local_pulls_remote(tmp_path: Path) -> None:
    assert sync(tmp_path, "a\n", None, "theirs\n") == ("pull", "theirs\n")


def test_missing_remote_pushes_local(tmp_path: Path) -> None:
    assert sync(tmp_path, "a\n", "mine\n", None) == ("push", "mine\n")


def test_missing_both_is_same(tmp_path: Path) -> None:
    assert sync(tmp_path, "a\n", None, None) == ("same", None)


def test_needs_push_and_conflict_markers(tmp_path: Path) -> None:
    local = tmp_path / "local"
    remote = tmp_path / "remote"
    local.write_text("a\n")
    remote.write_text("a\r\n")
    assert bash('artifact_needs_push "$1" "$2"', str(local), str(remote)).returncode == 1
    remote.write_text("b\n")
    assert bash('artifact_needs_push "$1" "$2"', str(local), str(remote)).returncode == 0
    remote.unlink()
    assert bash('artifact_needs_push "$1" "$2"', str(local), str(remote)).returncode == 0
    assert bash("artifact_has_conflict_markers \"$1\"", str(local)).returncode == 1
    local.write_text("<<<<<<< local\nx\n=======\ny\n>>>>>>> remote\n")
    assert bash("artifact_has_conflict_markers \"$1\"", str(local)).returncode == 0


def test_remote_paths_match_install_artifacts() -> None:
    result = bash('for f in "${ARTIFACT_FILES[@]}"; do artifact_remote_path "$f"; done')
    assert result.stdout.split() == ["SOUL.md", "memories/USER.md", "memories/MEMORY.md", "CV.md"]
