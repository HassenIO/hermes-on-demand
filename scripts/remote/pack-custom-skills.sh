#!/usr/bin/env bash
# Run on VPS: pack non-builtin skills under ~/.hermes/skills into a tar.gz.
# Usage: pack-custom-skills.sh /path/to/out.tgz
# Prints relative skill package paths (one per line) on stdout; tar path is arg.
set -euo pipefail

OUT="${1:?output tar.gz path required}"
HOME_SKILLS="${HERMES_HOME:-$HOME/.hermes}/skills"
BUILTIN="${HERMES_BUILTIN_SKILLS:-/usr/local/lib/hermes-agent/skills}"

python3 - "$HOME_SKILLS" "$BUILTIN" "$OUT" <<'PY'
import os
import sys
import tarfile
from pathlib import Path

home = Path(sys.argv[1]).expanduser().resolve()
builtin = Path(sys.argv[2])
out = Path(sys.argv[3])

if not home.is_dir():
    print(f"ERROR: missing skills dir: {home}", file=sys.stderr)
    sys.exit(1)

custom_roots: list[Path] = []
for skill_md in sorted(home.rglob("SKILL.md")):
    rel = skill_md.relative_to(home)
    if builtin.is_dir() and (builtin / rel).exists():
        continue
    custom_roots.append(skill_md.parent.resolve())

roots = sorted(set(custom_roots), key=lambda p: str(p))
if not roots:
    out.write_bytes(b"")
    sys.exit(0)


def should_include(path: Path) -> bool:
    name = path.name
    if name.startswith("."):
        return False
    if name == "README.md" or name.endswith(".sha256"):
        return False
    return True


out.parent.mkdir(parents=True, exist_ok=True)
with tarfile.open(out, mode="w:gz") as tar:
    for root in roots:
        rel_root = root.relative_to(home)
        print(rel_root.as_posix(), flush=True)
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = sorted(d for d in dirnames if should_include(Path(d)))
            for fn in sorted(filenames):
                fp = Path(dirpath) / fn
                if not should_include(fp) or not fp.is_file():
                    continue
                tar.add(fp, arcname=fp.relative_to(home).as_posix(), recursive=False)
PY
