"""Source common.sh. Do not rewrite load_dotenv or require_vars."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run_bash(script: str, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    child = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": os.environ.get("HOME", "/tmp"),
        "ROOT": str(ROOT),
    }
    child.update(env)
    return subprocess.run(
        ["bash", "-c", script],
        cwd=ROOT,
        env=child,
        capture_output=True,
        text=True,
    )


def test_load_dotenv_quotes_and_comments(tmp_path: Path) -> None:
    env_file = tmp_path / "sample.env"
    env_file.write_text(
        "\n".join(
            [
                "# comment",
                'FOO="bar baz"',
                "BAZ='qux'",
                "",
                "export QUX=ok",
                "# SKIP_ME=1",
                "",
            ]
        )
    )
    script = r"""
set -euo pipefail
source "$ROOT/scripts/lib/common.sh"
load_dotenv "$ENV_FILE"
printf 'FOO=%s\n' "$FOO"
printf 'BAZ=%s\n' "$BAZ"
printf 'QUX=%s\n' "$QUX"
if [[ "${SKIP_ME+x}" == x ]]; then
  echo "comment was loaded" >&2
  exit 1
fi
"""
    result = run_bash(script, {"ENV_FILE": str(env_file)})
    assert result.returncode == 0, result.stderr
    assert result.stdout == "FOO=bar baz\nBAZ=qux\nQUX=ok\n"


def test_require_vars_missing() -> None:
    script = r"""
set -euo pipefail
source "$ROOT/scripts/lib/common.sh"
require_vars MISSING_VAR_FOR_TEST
"""
    result = run_bash(script, {})
    assert result.returncode != 0
    assert "missing required env: MISSING_VAR_FOR_TEST" in result.stderr
