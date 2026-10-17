"""Cron shape checks. Calls validate_jobs, the function cron-push.sh calls."""

from __future__ import annotations

from pathlib import Path

import pytest

from cron_validate import summary_lines, validate_jobs

ROOT = Path(__file__).resolve().parents[1]


def job(job_id: str, name: str = "n", schedule: object | None = None) -> dict:
    body: dict = {"id": job_id, "name": name}
    if schedule is None:
        body["schedule"] = {"expr": "0 9 * * *"}
    else:
        body["schedule"] = schedule
    return body


@pytest.mark.parametrize(
    ("raw", "message"),
    [
        ({"jobs": []}, "cron/jobs.json must contain a non-empty jobs list"),
        ([], "cron/jobs.json must contain a non-empty jobs list"),
        (
            {"jobs": [{"name": "n", "schedule": {}}]},
            "job[0] needs an id",
        ),
        (
            {"jobs": [job("a"), job("a")]},
            "duplicate id: a",
        ),
        (
            {"jobs": [{"id": "a", "schedule": {}}]},
            "job a: missing name",
        ),
        (
            {"jobs": [{"id": "a", "name": "n", "schedule": "0 9 * * *"}]},
            "job a: schedule must be an object",
        ),
    ],
)
def test_cron_rejects(raw: object, message: str) -> None:
    with pytest.raises(SystemExit) as exc:
        validate_jobs(raw)
    assert exc.value.code == message


def test_cron_accepts_same_name_different_id() -> None:
    raw = {
        "jobs": [
            {"id": "a", "name": "same", "schedule": {"expr": "0 9 * * *"}},
            {"id": "b", "name": "same", "schedule": {"expr": "0 10 * * *"}},
        ]
    }
    jobs = validate_jobs(raw)
    assert [item["id"] for item in jobs] == ["a", "b"]
    assert jobs[0]["name"] == jobs[1]["name"] == "same"


def test_summary_matches_previous_stdout() -> None:
    jobs = validate_jobs(
        {"jobs": [{"id": "a", "name": "digest", "schedule": {"expr": "0 9 * * *"}}]}
    )
    assert summary_lines(jobs) == [
        "local_jobs=1",
        "  [on] a  digest  schedule=0 9 * * *",
    ]


def test_cron_push_calls_the_module_before_ssh() -> None:
    text = (ROOT / "scripts/cron-push.sh").read_text()
    assert "cron_validate.py" in text
    assert "must contain a non-empty jobs list" not in text
    assert text.index("cron_validate.py") < text.index('ssh_cmd "true"')


def test_remote_installer_keeps_its_own_validator() -> None:
    text = (ROOT / "scripts/remote/install-cron-jobs.sh").read_text()
    assert "from cron.jobs import" in text
    assert "duplicate job id:" in text
    assert "cron_validate" not in text
