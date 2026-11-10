"""S3 restore on fresh install. Source-text locks; no SSH, no Docker daemon, no network."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESTORE = ROOT / "scripts" / "remote" / "s3-restore.sh"
DEPLOY = ROOT / "scripts" / "deploy.sh"
SNAPSHOT = ROOT / "scripts" / "remote" / "s3-snapshot.sh"
UP = ROOT / "scripts" / "remote" / "hermes-docker-up.sh"
COMPOSE = ROOT / "docker" / "hermes" / "docker-compose.yml"
DOCS = ROOT / "docs" / "09-s3-snapshots.md"


def test_restore_is_add_only_and_gated_on_missing_jobs() -> None:
    text = RESTORE.read_text()
    assert text.startswith("#!/usr/bin/env bash")
    assert "set -euo pipefail" in text
    assert "source" in text and "common.sh" in text
    # fresh-install gate: existing jobs.json wins, nothing is overwritten
    assert 'if [[ -f "$JOBS" ]]; then' in text
    assert "nothing to restore" in text
    # never delete local state, never prune local skills, never sync --delete down
    assert "rm -rf $HERMES_HOME" not in text
    assert "--prune" not in text
    assert "sync" in text and "--delete" not in text
    # restores exactly the two mirrored artifacts
    assert "cron/jobs.json" in text
    assert "unpack-custom-skills.sh" in text
    assert "install-cron-jobs.sh" in text
    assert "pin-cron-models.sh" in text


def test_deploy_restores_before_gateway_start() -> None:
    text = DEPLOY.read_text()
    assert "s3-restore.sh" in text
    restore_at = text.index("s3-restore.sh")
    assert "S3_BUCKET" in text[:restore_at]
    # gated by the same four-variable condition
    gate_window = text[:restore_at].rsplit("if [[", 1)[-1]
    assert "S3_BUCKET" in gate_window and "AWS_DEFAULT_REGION" in gate_window
    # runs before the gateway/container starts, and warns rather than failing the deploy
    assert "gateway_refresh_ssh" in text[restore_at:]
    window = text[text.rfind("if [[", 0, restore_at) : restore_at + 400]
    assert "warn " in window


def test_restore_and_snapshot_are_counterparts() -> None:
    snap = SNAPSHOT.read_text()
    assert "s3-restore.sh" in snap  # header cross-reference


def test_cron_installer_knows_the_image_venv() -> None:
    installer = (ROOT / "scripts" / "remote" / "install-cron-jobs.sh").read_text()
    assert "/opt/hermes/.venv/bin/python" in installer


def test_container_gets_host_timezone_for_cron() -> None:
    compose = COMPOSE.read_text()
    assert "TZ: ${TZ}" in compose
    up = UP.read_text()
    assert "^TZ=" in up
    assert 'export TZ="' in up