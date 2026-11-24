#!/usr/bin/env bash
# Runs ON the VPS. Add every key between "# @hermes-tools" and
# "# @hermes-tools-end" in ~/.hermes/.env to terminal.docker_forward_env in
# ~/.hermes/config.yaml. Names only, never values.
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

MARKER, END_MARKER = "# @hermes-tools", "# @hermes-tools-end"
env_path, cfg_path = Path(sys.argv[1]), Path(sys.argv[2])

keys, in_section = [], False
for raw in env_path.read_text().splitlines():
    line = raw.strip()
    if line == MARKER:
        in_section = True
        continue
    if line == END_MARKER:
        break
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
fwd = next((i for i in range(term + 1, end) if re.match(r"( +)docker_forward_env:\s*$", lines[i])), None)
if fwd is None:
    lines.insert(term + 1, "  docker_forward_env:\n")
    fwd = term + 1
key_indent = len(lines[fwd]) - len(lines[fwd].lstrip(" "))

# Items may sit deeper than the key (config.yaml.example) or at the same
# indent (yaml.safe_dump, e.g. after notion-up). Insert with the same indent.
item_re = re.compile(r"( *)- *(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2\s*$")
pos, present, item_indent = fwd + 1, set(), None
while pos < len(lines):
    line = lines[pos]
    m = item_re.match(line)
    indent = len(line) - len(line.lstrip(" "))
    if m and indent >= key_indent and (item_indent is None or indent == item_indent):
        item_indent = indent
        present.add(m.group(3))
    elif not (line.lstrip().startswith("#") and indent > key_indent):
        break
    pos += 1
if item_indent is None:
    item_indent = key_indent + 2

missing = [k for k in keys if k not in present]
if missing:
    # Quoted so YAML never reads a name like ON, TRUE or NULL as a bool/null.
    lines[pos:pos] = [f'{" " * item_indent}- "{k}"\n' for k in missing]
    with cfg_path.open("w") as fh:
        fh.writelines(lines)
print(f"==> sandbox env: {len(keys)} tool key(s), {len(missing)} added to docker_forward_env")
PY
