#!/usr/bin/env bash
# Run on VPS: install a tar.gz of custom skills into ~/.hermes/skills.
# Refuses paths that collide with Hermes builtin skills.
# Usage: unpack-custom-skills.sh /path/to/skills.tgz [--prune]
#   --prune  remove remote custom skill packages not present in the archive
set -euo pipefail

TAR="${1:?tar.gz path required}"
PRUNE=0
[[ "${2:-}" == "--prune" ]] && PRUNE=1

HOME_SKILLS="${HERMES_HOME:-$HOME/.hermes}/skills"
BUILTIN="${HERMES_BUILTIN_SKILLS:-/usr/local/lib/hermes-agent/skills}"

python3 - "$HOME_SKILLS" "$BUILTIN" "$TAR" "$PRUNE" <<'PY'
import os
import shutil
import sys
import tarfile
import tempfile
from pathlib import Path

home = Path(sys.argv[1]).expanduser().resolve()
builtin = Path(sys.argv[2])
tar_path = Path(sys.argv[3])
prune = sys.argv[4] == "1"

if not tar_path.is_file() or tar_path.stat().st_size == 0:
    print("ERROR: missing or empty tar", file=sys.stderr)
    sys.exit(1)

home.mkdir(parents=True, exist_ok=True)


def is_builtin_rel(rel: Path) -> bool:
    if not builtin.is_dir():
        return False
    return (builtin / rel).exists()


def skill_roots_under(base: Path) -> list[Path]:
    roots: list[Path] = []
    for skill_md in base.rglob("SKILL.md"):
        roots.append(skill_md.parent.resolve())
    return sorted(set(roots), key=lambda p: str(p))


staging = Path(tempfile.mkdtemp(prefix="hermes-skills-unpack-"))
try:
    with tarfile.open(tar_path, mode="r:gz") as tar:
        # Safety: no absolute paths / path escape
        for m in tar.getmembers():
            name = m.name
            if name.startswith("/") or ".." in Path(name).parts:
                print(f"ERROR: unsafe tar member: {name}", file=sys.stderr)
                sys.exit(1)
        tar.extractall(staging)

    incoming = skill_roots_under(staging)
    if not incoming:
        print("ERROR: archive contains no SKILL.md packages", file=sys.stderr)
        sys.exit(1)

    installed: list[str] = []
    for root in incoming:
        rel = root.relative_to(staging)
        # Collision: any path under this package mirrors a builtin SKILL.md
        if is_builtin_rel(rel / "SKILL.md") or (
            builtin.is_dir() and (builtin / rel).exists() and (builtin / rel / "SKILL.md").exists()
        ):
            print(f"ERROR: refuses builtin path: {rel.as_posix()}", file=sys.stderr)
            sys.exit(1)
        # Also block if the package path itself is a builtin skill dir
        for p in [rel, *rel.parents]:
            if p == Path("."):
                continue
            if is_builtin_rel(p / "SKILL.md"):
                print(f"ERROR: refuses builtin path: {p.as_posix()}", file=sys.stderr)
                sys.exit(1)

        dest = home / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        if dest.exists():
            shutil.rmtree(dest)
        shutil.copytree(root, dest)
        # Drop hermes bookkeeping sidecars if any slipped in
        for side in dest.rglob("*.sha256"):
            side.unlink(missing_ok=True)
        for readme in dest.rglob("README.md"):
            readme.unlink(missing_ok=True)
        installed.append(rel.as_posix())
        print(f"installed {rel.as_posix()}", flush=True)

    if prune:
        remote_custom = []
        for skill_md in home.rglob("SKILL.md"):
            rel = skill_md.relative_to(home)
            if is_builtin_rel(rel):
                continue
            remote_custom.append(skill_md.parent.resolve())
        keep = { (home / Path(p)).resolve() for p in installed }
        for root in sorted(set(remote_custom), key=lambda p: str(p), reverse=True):
            if root in keep:
                continue
            rel = root.relative_to(home)
            shutil.rmtree(root)
            print(f"pruned {rel.as_posix()}", flush=True)
            # remove empty parents under home (not home itself)
            parent = root.parent
            while parent != home and parent.is_dir() and not any(parent.iterdir()):
                parent.rmdir()
                parent = parent.parent
finally:
    shutil.rmtree(staging, ignore_errors=True)
PY
