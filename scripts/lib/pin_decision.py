#!/usr/bin/env python3
"""Pin or skip classification for cron model pinning. Does not call hermes."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def is_force(value: str) -> bool:
    return str(value).strip() in ("1", "true", "yes")


def classify_job(job: object, target: str, force: bool) -> str | None:
    """Return 'pin', 'skip', or None when the job has no id."""
    if not isinstance(job, dict) or not job.get("id"):
        return None
    current = (job.get("model") or "").strip()
    wanted = (target or "").strip()
    if force or not current or current == wanted:
        return "pin"
    return "skip"


def decision_line(job: dict, target: str, force: bool) -> str | None:
    action = classify_job(job, target, force)
    if action is None:
        return None
    job_id = job["id"]
    name = (job.get("name") or job_id)[:48]
    if action == "pin":
        return f"pin\t{job_id}\t{name}"
    current = (job.get("model") or "").strip()
    return f"skip\t{job_id}\t{name}\t{current}"


def load_jobs(path: Path) -> list | None:
    """Match the previous inline loader: missing or non-list means nothing to pin."""
    if not path.exists():
        return None
    data = json.loads(path.read_text())
    jobs = data.get("jobs") if isinstance(data, dict) else data
    if isinstance(jobs, dict):
        jobs = list(jobs.values())
    if not isinstance(jobs, list):
        return None
    return jobs


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv
    if len(argv) != 4:
        print("usage: pin_decision.py JOBS_JSON MODEL FORCE", file=sys.stderr)
        return 2
    jobs = load_jobs(Path(argv[1]))
    if not jobs:
        return 0
    force = is_force(argv[3])
    for job in jobs:
        line = decision_line(job, argv[2], force)
        if line:
            print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
