# Local unit tests

`make test` checks decisions that must be right before any SSH. It does not deploy, and it does not talk to a VPS.

End-to-end deploy checks belong in [10-deployment-testing](10-deployment-testing.md). Do not add those tests here.

## What this covers

The suite calls the same function the script calls. A test that restates the rule will still pass after the script drifts. Do not do that.

| Decision | Function | Defined in | Called by |
|----------|----------|------------|-----------|
| Localhost refusal | `refuse_local_target` | `scripts/lib/runtime-env.sh` | `scripts/deploy.sh` |
| Runtime env filter | `build_runtime_env` | `scripts/lib/runtime-env.sh` | `scripts/deploy.sh` |
| Cron job shape, before SSH | `validate_jobs` | `scripts/lib/cron_validate.py` | `scripts/cron-push.sh` |
| Cron model pin or skip | `classify_job` | `scripts/lib/pin_decision.py` | `scripts/remote/pin-cron-models.sh` |
| Config invariants | `config/config.yaml.example` | asserted, not executed |
| Ignore rules | `.gitignore` via `git check-ignore` | |
| Makefile contract | `Makefile` | |
| Skill unpack | `scripts/remote/unpack-custom-skills.sh` | temp dir only |

`load_dotenv` and `require_vars` live in `scripts/lib/common.sh`. Tests source that file. Do not rewrite it to make a test easier.

Cron jobs need a unique `id`. Names are not required to be unique. Do not add that check.

`scripts/remote/install-cron-jobs.sh` keeps its own validator and its Hermes import. The suite owns the local gate that runs before SSH. Do not import Hermes in these tests.

## When to run it

Run `make test` before a feature that touches those functions, the cron validator, or the pin decision. If the decision changes, extend `tests/` in the same change. Do not weaken or skip a test to land the feature.

`make lint` is `bash -n` on every script under `scripts/`. Run `make install-hooks` once per clone. After that, `git commit` runs `make lint` and `make test` and stops if either fails. Do not pass `--no-verify` to skip it. Every pull request push also runs both in `.github/workflows/pr-checks.yml`. The comment is written by `scripts/ci/pr-comment.mjs`. Do not paste that logic back into the workflow. Do not add deployment, health, or network tests to that workflow.

## Out of scope

No deployment, health, or Telegram tests. No Docker, SSH, or network. Do not unit-test SSH modes or what `SKIP_*` does on a full deploy. Do not test `notion_cli.py`.

`make test` does not read `.env` and does not open SSH. Do not point a test at a host, a bot, or Docker.

## How to run

Python 3.12 or newer. `uv` is required. Pytest is the `dev` dependency group in `pyproject.toml`. From the repo root:

```bash
make test
```

That runs `uv run --no-env-file pytest`. `--no-env-file` is required so uv does not load `.env`. Do not run pytest through pip or a system `python3 -m pytest`.

The tests do not install Hermes.
