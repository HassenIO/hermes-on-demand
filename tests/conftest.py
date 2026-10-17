"""Keep the suite local: no SSH, no sockets, no bytecode next to scripts."""

from __future__ import annotations

import os
import stat
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "scripts" / "lib"
if str(LIB) not in sys.path:
    sys.path.insert(0, str(LIB))

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"

import pytest  # noqa: E402


@pytest.fixture(autouse=True, scope="session")
def reject_ssh(tmp_path_factory):
    bindir = tmp_path_factory.mktemp("no-ssh")
    stamp = bindir / "invoked"
    for name in ("ssh", "scp"):
        path = bindir / name
        path.write_text(
            "#!/bin/sh\n"
            f"echo \"$0 $*\" >> '{stamp}'\n"
            "echo 'refusing ssh in unit tests' >&2\n"
            "exit 99\n"
        )
        path.chmod(path.stat().st_mode | stat.S_IEXEC)
    os.environ["PATH"] = str(bindir) + os.pathsep + os.environ.get("PATH", "")
    yield stamp
    if stamp.exists() and stamp.read_text().strip():
        raise AssertionError(f"ssh/scp invoked during tests:\n{stamp.read_text()}")


@pytest.fixture(autouse=True)
def reject_sockets(monkeypatch):
    import socket

    def blocked(*_args, **_kwargs):
        raise AssertionError("unit test opened a socket")

    monkeypatch.setattr(socket, "socket", blocked)
    monkeypatch.setattr(socket, "create_connection", blocked)
