"""Run unpack-custom-skills.sh in a temp dir. Do not change its rules."""

from __future__ import annotations

import io
import os
import subprocess
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UNPACK = ROOT / "scripts" / "remote" / "unpack-custom-skills.sh"


def make_tar(path: Path, files: dict[str, str]) -> None:
    with tarfile.open(path, "w:gz") as tar:
        for name, content in files.items():
            data = content.encode()
            info = tarfile.TarInfo(name)
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))


def run_unpack(tar_path: Path, home: Path, builtin: Path, prune: bool) -> subprocess.CompletedProcess[str]:
    argv = ["bash", str(UNPACK), str(tar_path)]
    if prune:
        argv.append("--prune")
    # macOS /var → /private/var. The script resolves skill roots but not its
    # staging dir, so TMPDIR must already be the real path or relative_to fails.
    scratch = home.parent / "scratch"
    scratch.mkdir(exist_ok=True)
    env = os.environ.copy()
    env["HOME"] = str(home)
    env["HERMES_HOME"] = str(home)
    env["HERMES_BUILTIN_SKILLS"] = str(builtin)
    env["TMPDIR"] = str(scratch.resolve())
    return subprocess.run(argv, cwd=ROOT, env=env, capture_output=True, text=True)


def test_unpack_drops_readme_and_prunes_extra(tmp_path: Path) -> None:
    home = tmp_path / "hermes"
    skills = home / "skills"
    extra = skills / "stale-skill"
    extra.mkdir(parents=True)
    (extra / "SKILL.md").write_text("---\nname: stale\n---\n")

    builtin = tmp_path / "builtin"
    builtin.mkdir()
    archive = tmp_path / "skills.tgz"
    make_tar(
        archive,
        {
            "custom-skill/SKILL.md": "---\nname: custom\n---\n",
            "custom-skill/README.md": "do not install\n",
        },
    )

    result = run_unpack(archive, home, builtin, prune=True)
    assert result.returncode == 0, result.stderr
    assert (skills / "custom-skill" / "SKILL.md").is_file()
    assert not (skills / "custom-skill" / "README.md").exists()
    assert list(skills.rglob("README.md")) == []
    assert not extra.exists()
    assert "installed custom-skill" in result.stdout
    assert "pruned stale-skill" in result.stdout


def test_unpack_refuses_builtin_path(tmp_path: Path) -> None:
    home = tmp_path / "hermes"
    builtin = tmp_path / "builtin"
    (builtin / "builtin-skill").mkdir(parents=True)
    (builtin / "builtin-skill" / "SKILL.md").write_text("builtin\n")
    archive = tmp_path / "skills.tgz"
    make_tar(archive, {"builtin-skill/SKILL.md": "custom copy\n"})

    result = run_unpack(archive, home, builtin, prune=False)
    assert result.returncode != 0
    assert "refuses builtin path: builtin-skill" in result.stderr
    assert not (home / "skills" / "builtin-skill").exists()


PACK = ROOT / "scripts" / "remote" / "pack-custom-skills.sh"


def write_manifest_builtin(skills: Path) -> Path:
    """A builtin known only from .bundled_manifest, as under the Docker runtime."""
    skill = skills / "software-development" / "github"
    skill.mkdir(parents=True)
    (skill / "SKILL.md").write_text("---\nname: github\n---\n")
    (skills / ".bundled_manifest").write_text("github:abc123\n")
    return skill


def test_unpack_keeps_manifest_builtin_on_prune(tmp_path: Path) -> None:
    home = tmp_path / "hermes"
    github = write_manifest_builtin(home / "skills")
    archive = tmp_path / "skills.tgz"
    make_tar(archive, {"custom-skill/SKILL.md": "---\nname: custom\n---\n"})

    result = run_unpack(archive, home, tmp_path / "no-builtin-tree", prune=True)
    assert result.returncode == 0, result.stderr
    assert (github / "SKILL.md").is_file()
    assert "pruned" not in result.stdout


def test_unpack_refuses_manifest_builtin(tmp_path: Path) -> None:
    home = tmp_path / "hermes"
    write_manifest_builtin(home / "skills")
    archive = tmp_path / "skills.tgz"
    make_tar(archive, {"software-development/github/SKILL.md": "custom copy\n"})

    result = run_unpack(archive, home, tmp_path / "no-builtin-tree", prune=False)
    assert result.returncode != 0
    assert "refuses builtin path: software-development/github" in result.stderr


def test_pack_skips_manifest_builtin(tmp_path: Path) -> None:
    home = tmp_path / "hermes"
    skills = home / "skills"
    write_manifest_builtin(skills)
    (skills / "software-development" / "factory").mkdir(parents=True)
    (skills / "software-development" / "factory" / "SKILL.md").write_text("---\nname: factory\n---\n")
    out = tmp_path / "out.tgz"
    env = os.environ.copy()
    env["HERMES_HOME"] = str(home)
    env["HERMES_BUILTIN_SKILLS"] = str(tmp_path / "no-builtin-tree")

    result = subprocess.run(["bash", str(PACK), str(out)], cwd=ROOT, env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert result.stdout.split() == ["software-development/factory"]
    with tarfile.open(out) as tar:
        assert tar.getnames() == ["software-development/factory/SKILL.md"]

