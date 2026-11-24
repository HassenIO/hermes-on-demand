"""scripts/remote/apply-sandbox-env.sh: tool keys from ~/.hermes/.env into docker_forward_env."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "remote" / "apply-sandbox-env.sh"
EXAMPLE = ROOT / "config" / "config.yaml.example"


def run(home: Path) -> subprocess.CompletedProcess[str]:
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": str(home), "HERMES_HOME": str(home)}
    return subprocess.run(["bash", str(SCRIPT)], env=env, capture_output=True, text=True)


def forward_list(cfg: str) -> list[str]:
    lines = cfg.splitlines()
    start = lines.index("  docker_forward_env:")
    items = []
    for line in lines[start + 1 :]:
        stripped = line.strip()
        if stripped.startswith("- "):
            items.append(stripped[2:].strip().strip('"'))
        elif not (stripped.startswith("#") and line.startswith("    ")):
            break
    return items


def test_adds_tool_keys_once_and_keeps_values_out(tmp_path: Path) -> None:
    (tmp_path / ".env").write_text(
        "OPENROUTER_API_KEY=core\n# @hermes-tools\nSOME_TOOL_API_KEY=secret\nGITHUB_TOKEN=gh\n# @hermes-tools-end\n"
    )
    (tmp_path / "config.yaml").write_text(EXAMPLE.read_text())
    before = forward_list(EXAMPLE.read_text())

    for _ in range(2):
        result = run(tmp_path)
        assert result.returncode == 0, result.stderr

    cfg = (tmp_path / "config.yaml").read_text()
    after = forward_list(cfg)
    assert after == before + ["SOME_TOOL_API_KEY"]
    assert "OPENROUTER_API_KEY" not in after
    assert "secret" not in cfg
    rest = EXAMPLE.read_text().replace("    - CLAUDE_CODE_OAUTH_TOKEN\n", "    - CLAUDE_CODE_OAUTH_TOKEN\n    - \"SOME_TOOL_API_KEY\"\n")
    assert cfg == rest


def test_no_marker_leaves_config_untouched(tmp_path: Path) -> None:
    (tmp_path / ".env").write_text("SOME_TOOL_API_KEY=secret\n")
    (tmp_path / "config.yaml").write_text(EXAMPLE.read_text())
    result = run(tmp_path)
    assert result.returncode == 0, result.stderr
    assert (tmp_path / "config.yaml").read_text() == EXAMPLE.read_text()


def test_deploy_and_bootstrap_apply_after_writing_config() -> None:
    for script, write in (
        (ROOT / "scripts" / "deploy.sh", "config.yaml.example' \"\\$HERMES_HOME/config.yaml\""),
        (ROOT / "scripts" / "remote" / "bootstrap.sh", '"$CONFIG_SRC" "$HERMES_HOME/config.yaml"'),
    ):
        text = script.read_text()
        assert text.index("apply-sandbox-env.sh") > text.index(write), script.name


def test_lines_appended_after_end_marker_are_not_forwarded(tmp_path: Path) -> None:
    # mnemosyne-up appends HERMES_HOME and MNEMOSYNE_DATA_DIR at the end of .env.
    (tmp_path / ".env").write_text(
        "# @hermes-tools\nSOME_TOOL_API_KEY=s\n# @hermes-tools-end\nHERMES_HOME=/root/.hermes\nMNEMOSYNE_DATA_DIR=/x\n"
    )
    (tmp_path / "config.yaml").write_text(EXAMPLE.read_text())
    assert run(tmp_path).returncode == 0
    after = forward_list((tmp_path / "config.yaml").read_text())
    assert "SOME_TOOL_API_KEY" in after
    assert "HERMES_HOME" not in after
    assert "MNEMOSYNE_DATA_DIR" not in after


def test_same_indent_list_from_yaml_dump_stays_valid(tmp_path: Path) -> None:
    # notion-up rewrites config.yaml with yaml.safe_dump: items at the key's indent.
    cfg = "terminal:\n  backend: docker\n  docker_forward_env:\n  - GITHUB_TOKEN\n  - \"OLD_KEY\"\n  docker_env:\n    PATH: /bin\n"
    (tmp_path / ".env").write_text("# @hermes-tools\nOLD_KEY=a\nNEW_KEY=b\n# @hermes-tools-end\n")
    (tmp_path / "config.yaml").write_text(cfg)
    for _ in range(2):
        assert run(tmp_path).returncode == 0
    assert (tmp_path / "config.yaml").read_text() == cfg.replace(
        '  - "OLD_KEY"\n', '  - "OLD_KEY"\n  - "NEW_KEY"\n'
    )


def test_yaml_keyword_names_are_quoted(tmp_path: Path) -> None:
    (tmp_path / ".env").write_text("# @hermes-tools\nON=a\nTRUE=b\nNULL=c\n# @hermes-tools-end\n")
    (tmp_path / "config.yaml").write_text(EXAMPLE.read_text())
    assert run(tmp_path).returncode == 0
    cfg = (tmp_path / "config.yaml").read_text()
    for name in ("ON", "TRUE", "NULL"):
        assert f'    - "{name}"\n' in cfg
        assert f"    - {name}\n" not in cfg


def test_notion_up_does_not_source_the_env_file() -> None:
    text = (ROOT / "scripts" / "remote" / "notion-up.sh").read_text()
    assert 'source "$ENV_FILE"' not in text
    assert 'load_dotenv "$ENV_FILE"' in text
