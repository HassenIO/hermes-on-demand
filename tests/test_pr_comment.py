"""Report text for the pull request comment. Does not call GitHub."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_report_body_and_failure_flag() -> None:
    script = r"""
import { reportBody, checksFailed, clip, writeDenied } from "./scripts/ci/pr-comment.mjs";
const body = reportBody({
  lint: "success",
  test: "failure",
  lintLog: "ok",
  testLog: "bad",
  sha: "abc",
});
const result = {
  marker: body.includes("<!-- hermes-pr-checks -->"),
  lint: body.includes("| Lint (`make lint`) | pass |"),
  test: body.includes("| Tests (`make test`) | fail |"),
  failed: checksFailed("success", "failure"),
  passed: checksFailed("success", "success"),
  empty: clip(""),
  denied: writeDenied(403),
  other: writeDenied(500),
};
process.stdout.write(JSON.stringify(result));
"""
    result = subprocess.run(
        ["node", "--input-type=module", "-e", script],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    assert payload == {
        "marker": True,
        "lint": True,
        "test": True,
        "failed": True,
        "passed": False,
        "empty": "_no output_",
        "denied": True,
        "other": False,
    }
