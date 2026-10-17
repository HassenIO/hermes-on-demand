"""Localhost guard. Calls refuse_local_target, the function deploy.sh calls."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
LOCAL_HOSTS = ("localhost", "127.0.0.1", "::1")


def run_guard(host: str, allow: str | None = None) -> subprocess.CompletedProcess[str]:
    script = f"""
set -euo pipefail
source "{ROOT}/scripts/lib/runtime-env.sh"
refuse_local_target
"""
    env = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": os.environ.get("HOME", "/tmp"),
        "TARGET_HOST": host,
    }
    if allow is not None:
        env["ALLOW_LOCAL_TARGET"] = allow
    return subprocess.run(
        ["bash", "-c", script],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
    )


@pytest.mark.parametrize("host", LOCAL_HOSTS)
def test_local_host_refused(host: str) -> None:
    result = run_guard(host)
    assert result.returncode != 0
    assert result.stderr.strip() == (
        f"ERROR: refusing TARGET_HOST={host} (set ALLOW_LOCAL_TARGET=1 to override)"
    )


@pytest.mark.parametrize("host", LOCAL_HOSTS)
def test_local_override_allows(host: str) -> None:
    result = run_guard(host, allow="1")
    assert result.returncode == 0
    assert result.stderr == ""


def test_other_host_allowed() -> None:
    result = run_guard("example.vps")
    assert result.returncode == 0
    assert result.stderr == ""


def test_deploy_calls_the_guard_before_ssh() -> None:
    text = (ROOT / "scripts/deploy.sh").read_text()
    lib = (ROOT / "scripts/lib/runtime-env.sh").read_text()
    assert "\nrefuse_local_target\n" in text
    assert "refusing TARGET_HOST" not in text
    assert "refusing TARGET_HOST" in lib
    assert text.index("refuse_local_target") < text.index('log "SSH probe')
    assert 'ssh_cmd "true"' in text
