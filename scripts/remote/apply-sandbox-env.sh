#!/usr/bin/env bash
# Runs ON the VPS. Add every key below "# @hermes-tools" in ~/.hermes/.env to
# terminal.docker_forward_env in ~/.hermes/config.yaml. Names only, never values.
# Idempotent. Run after config.yaml is written from config.yaml.example.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
ENV_PATH="$HERMES_HOME/.env"
CFG="$HERMES_HOME/config.yaml"

[[ -f "$ENV_PATH" ]] || { warn "missing $ENV_PATH — skip sandbox env"; exit 0; }
[[ -f "$CFG" ]] || { warn "missing $CFG — skip sandbox env"; exit 0; }

python3 - "$ENV_PATH" "$CFG" <<'PY'
import re
import sys
from pathlib import Path

MARKER = "# @hermes-tools"
env_path, cfg_path = Path(sys.argv[1]), Path(sys.argv[2])

keys, in_section = [], False
for raw in env_path.read_text().splitlines():
    line = raw.strip()
    if line == MARKER:
        in_section = True
        continue
    if in_section and "=" in line and not line.startswith("#"):
        key = line.split("=", 1)[0].strip()
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key) and key not in keys:
            keys.append(key)
if not keys:
    raise SystemExit(0)

lines = cfg_path.read_text().splitlines(keepends=True)
term = next((i for i, l in enumerate(lines) if re.match(r"terminal:\s*$", l)), None)
if term is None:
    print("!!  no terminal: block in config.yaml — skip sandbox env", file=sys.stderr)
    raise SystemExit(0)

end = next((i for i in range(term + 1, len(lines)) if re.match(r"\S", lines[i])), len(lines))
fwd = next((i for i in range(term + 1, end) if re.match(r"  docker_forward_env:\s*$", lines[i])), None)
if fwd is None:
    lines.insert(term + 1, "  docker_forward_env:\n")
    fwd = term + 1

pos, present = fwd + 1, set()
while pos < len(lines):
    m = re.match(r"    - (\S+)\s*$", lines[pos])
    if m:
        present.add(m.group(1))
    elif not re.match(r"    #", lines[pos]):
        break
    pos += 1

missing = [k for k in keys if k not in present]
if missing:
    lines[pos:pos] = [f"    - {k}\n" for k in missing]
    with cfg_path.open("w") as fh:
        fh.writelines(lines)
print(f"==> sandbox env: {len(keys)} tool key(s), {len(missing)} added to docker_forward_env")
PY
