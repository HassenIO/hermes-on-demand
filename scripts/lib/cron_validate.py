#!/usr/bin/env python3
"""Pre-SSH cron/jobs.json checks. Error strings are the cron-push contract."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def validate_jobs(raw: object) -> list:
    """Return the jobs list, or raise SystemExit with the existing error text."""
    jobs = raw.get("jobs", raw) if isinstance(raw, dict) else raw
    if not isinstance(jobs, list) or not jobs:
        raise SystemExit("cron/jobs.json must contain a non-empty jobs list")
    ids: set = set()
    for i, job in enumerate(jobs):
        if not isinstance(job, dict) or not job.get("id"):
            raise SystemExit(f"job[{i}] needs an id")
        if job["id"] in ids:
            raise SystemExit(f"duplicate id: {job['id']}")
        ids.add(job["id"])
        if not job.get("name"):
            raise SystemExit(f"job {job['id']}: missing name")
        if not isinstance(job.get("schedule"), dict):
            raise SystemExit(f"job {job['id']}: schedule must be an object")
    return jobs


def summary_lines(jobs: list) -> list[str]:
    lines = [f"local_jobs={len(jobs)}"]
    for job in jobs:
        enabled = "on" if job.get("enabled", True) else "off"
        schedule = job.get("schedule_display") or (job.get("schedule") or {}).get("expr") or "?"
        lines.append(f"  [{enabled}] {job['id']}  {job.get('name')}  schedule={schedule}")
    return lines


def main(argv: list[str] | None = None) -> None:
    if argv is None:
        argv = sys.argv
    raw = json.loads(Path(argv[1]).read_text(encoding="utf-8"))
    jobs = validate_jobs(raw)
    for line in summary_lines(jobs):
        print(line)


if __name__ == "__main__":
    main()
