"""Pin/skip classification. Calls classify_job, the function the pin script calls."""

from __future__ import annotations

from pathlib import Path

import pytest

from pin_decision import classify_job, decision_line, is_force

ROOT = Path(__file__).resolve().parents[1]
TARGET = "xiaomi/mimo-v2.5"


def test_pin_skip_when_model_differs() -> None:
    job = {"id": "j1", "name": "write", "model": "other/model"}
    assert is_force("0") is False
    assert classify_job(job, TARGET, force=False) == "skip"


def test_pin_when_model_empty_or_equal() -> None:
    assert classify_job({"id": "j1", "model": ""}, TARGET, False) == "pin"
    assert classify_job({"id": "j1"}, TARGET, False) == "pin"
    assert classify_job({"id": "j1", "model": "   "}, TARGET, False) == "pin"
    assert classify_job({"id": "j1", "model": TARGET}, TARGET, False) == "pin"


@pytest.mark.parametrize("value", ["1", "true", "yes", " yes "])
def test_pin_force(value: str) -> None:
    assert is_force(value) is True
    jobs = [
        {"id": "a", "model": "other/model"},
        {"id": "b", "model": ""},
        {"id": "c", "model": TARGET},
    ]
    assert [classify_job(job, TARGET, force=True) for job in jobs] == ["pin", "pin", "pin"]


def test_force_rejects_other_spellings() -> None:
    assert is_force("True") is False
    assert is_force("YES") is False
    assert is_force("") is False
    assert is_force("false") is False


def test_job_without_id_is_not_classified() -> None:
    assert classify_job({"name": "n", "model": "other"}, TARGET, False) is None


def test_decision_line_matches_shell_split() -> None:
    pinned = decision_line({"id": "a", "name": "n", "model": ""}, TARGET, False)
    assert pinned is not None
    assert pinned.split("\t") == ["pin", "a", "n"]
    skipped = decision_line({"id": "a", "name": "n", "model": "other"}, TARGET, False)
    assert skipped is not None
    assert skipped.split("\t") == ["skip", "a", "n", "other"]
    long_name = "n" * 60
    truncated = decision_line({"id": "a", "name": long_name, "model": ""}, TARGET, False)
    assert truncated is not None
    assert truncated.split("\t")[2] == "n" * 48


def test_pin_script_calls_the_module_and_still_needs_hermes_to_edit() -> None:
    text = (ROOT / "scripts/remote/pin-cron-models.sh").read_text()
    assert "pin_decision.py" in text
    assert 'in ("1", "true", "yes")' not in text
    assert "command -v hermes" in text
    assert "hermes cron edit" in text
