"""Copilot review request on pull request open. Does not call GitHub."""

from __future__ import annotations

import json
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "pr-checks.yml"
SCRIPT = ROOT / "scripts" / "ci" / "request-copilot-review.mjs"


def _steps(text: str) -> list[str]:
    return re.split(r"\n      - ", text.split("\n    steps:\n", 1)[1])


def test_request_decision_and_payload() -> None:
    script = r"""
import { shouldRequest, reviewPayload, warning } from "./scripts/ci/request-copilot-review.mjs";
process.stdout.write(JSON.stringify({
  opened: shouldRequest("opened"),
  synchronize: shouldRequest("synchronize"),
  reopened: shouldRequest("reopened"),
  payload: reviewPayload(),
  warning: warning("boom"),
}));
"""
    result = subprocess.run(
        ["node", "--input-type=module", "-e", script],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout) == {
        "opened": True,
        "synchronize": False,
        "reopened": False,
        "payload": {"reviewers": ["copilot-pull-request-reviewer[bot]"]},
        "warning": "::warning title=Copilot review::boom",
    }


def _run_script(tmp_path: Path, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    base = {k: v for k, v in os.environ.items() if not k.startswith(("GITHUB_", "GH_"))}
    return subprocess.run(
        ["node", str(SCRIPT)],
        cwd=tmp_path,
        env={**base, **env},
        capture_output=True,
        text=True,
        check=False,
    )


def test_non_opened_event_skips_without_request(tmp_path: Path) -> None:
    event = tmp_path / "event.json"
    event.write_text(json.dumps({"action": "synchronize", "pull_request": {"number": 7}}))
    result = _run_script(
        tmp_path,
        {
            "GITHUB_TOKEN": "placeholder",
            "GITHUB_REPOSITORY": "owner/repo",
            "GITHUB_EVENT_PATH": str(event),
        },
    )
    assert result.returncode == 0, result.stderr
    assert "not requested" in result.stdout


def test_failure_warns_and_exits_zero(tmp_path: Path) -> None:
    result = _run_script(tmp_path, {})
    assert result.returncode == 0, result.stderr
    assert result.stdout.startswith("::warning title=Copilot review::")


def test_workflow_requests_review_last_on_opened_only() -> None:
    text = WORKFLOW.read_text()
    steps = _steps(text)
    review = steps[-1]
    assert "name: Request Copilot review" in review
    assert "node scripts/ci/request-copilot-review.mjs" in review
    assert "if: always() && github.event.action == 'opened'" in review
    assert "continue-on-error: true" in review
    assert "pr-comment.mjs" in steps[-2]


def test_follow_up_push_cannot_cancel_opened_run() -> None:
    text = WORKFLOW.read_text()
    assert (
        "group: pr-checks-${{ github.event.pull_request.number }}-"
        "${{ github.event.action == 'opened' && 'opened' || 'updates' }}"
    ) in text


def test_workflow_permissions_stay_minimal() -> None:
    text = WORKFLOW.read_text()
    block = text.split("\npermissions:\n", 1)[1].split("\n\n", 1)[0]
    lines = sorted(line.strip() for line in block.splitlines() if line.strip())
    assert lines == ["contents: read", "pull-requests: write"]
