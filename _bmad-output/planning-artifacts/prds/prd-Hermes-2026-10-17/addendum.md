---
title: Hermes control plane — addendum
status: draft
created: 2026-10-17
updated: 2026-10-17
---

# Addendum: Hermes control plane

Mechanism, conflict log, and inventories that do not belong in the PRD. The PRD is the requirements baseline. This file is how the tree implements it today (2026-10-17).

## A. Which source won

| Conflict | PRD follows | Why |
|---|---|---|
| `README.md` says artifact push is seeds only. Code also syncs payload, applies timezone, and restarts the gateway. | Code and `AGENTS.md` | The Makefile help line is the accurate operator contract. |
| `README.md` calls `setup-notion` a no-op unless both Notion vars are set. Code still syncs payload and applies timezone. | Code | The Notion install is the no-op. The shared preamble is not. |
| `docs/02-deploy.md` full-deploy list stops before Agent-Reach, Notion, timezone, cron pin, and conditional snapshot. | `deploy.sh` | The doc is stale. |
| `docs/02-deploy.md` says artifact mode is profile files only, and that scripts refuse localhost. | Code | Only `deploy.sh` refuses the control-plane machine. `ssh`, skills, and cron do not. |
| `docs/03-configuration.md` lists `TIMEZONE` as never written to the runtime env. | `build_runtime_env` | `TIMEZONE` and `TZ` are always written. |
| `docs/11-testing.md` and `AGENTS.md` say cron names need not be unique. `docs/10-deployment-testing.md` says they must. | Validator | Do not add a unique-name check. |
| `extensions/README.md` types Notion as MCP. `notion-up.sh` installs a REST CLI and disables Notion MCP. | `notion-up.sh` | MCP is a non-goal. |
| `README.md` says control can run on a CI/CD pipeline. The only workflow is lint and test. | Workflow | CI deploy is a non-goal. |
| Allow-all "never true" in `AGENTS.md` and gateway docs. Filter copies the var if set, including `true`. | Split | Published defaults must omit it. Refusing an explicit true is Open Question 1. |
| `extensions/registry.yaml` calls itself source of truth. No script loads it. | Code | Registration is the `deploy.sh` case and the Make target until a loader exists. |

## B. Operator surface today

Make targets in `Makefile`. All are `.PHONY` and have a `##` help line.

| Target | Mode | Gateway restart | Localhost refuse |
|---|---|---|---|
| `help`, `check-env`, `lint`, `test` | local | no | n/a |
| `ssh` | interactive SSH | no | no |
| `skills-pull`, `skills-push`, `cron-pull`, `cron-push` | rsync/ssh | no | no |
| `deploy`, `full` | `scripts/deploy.sh` full | yes, possibly several | yes |
| `push-config` | config-only | yes | yes |
| `push-artifacts` | artifacts | yes | yes |
| `health` | health | no | yes |
| `update` | update | yes | yes |
| `s3-snapshot` | snapshot | no | yes |
| `setup-firecrawl`, `setup-mnemosyne`, `setup-agent-reach`, `setup-notion` | matching flag | yes, from the extension script | yes |

`refuse_local_target` covers `localhost`, `127.0.0.1`, and `::1`, overridable with `ALLOW_LOCAL_TARGET=1`. Deploy SSH uses `BatchMode=yes` and `StrictHostKeyChecking=accept-new`. `make ssh` does not set `BatchMode` and can prompt for a password. `deploy.sh` `scp_cmd` has neither `BatchMode` nor `StrictHostKeyChecking`. Skills and cron SSH do set both; the skills-push `scp` does not set `BatchMode`.

Every `deploy.sh` mode except health requires `TARGET_HOST`, `TARGET_USER`, `OPENROUTER_API_KEY`, `TELEGRAM_BOT_TOKEN`, and `TELEGRAM_ALLOWED_USERS`, then syncs payload and runs `set-timezone.sh`. Health runs the copy of `healthcheck.sh` already on the agent host. It does not upload, does not apply timezone, and does not restart. It reapplies the session-path patch only if the marker is missing, and it can relink a broken `~/.local/bin/hermes`.

Full deploy order: `bootstrap.sh` (apt, Docker, official installer `--skip-browser`, CLI relink, runtime env mode 600, config, seeds, session-path patch, user gateway plus linger, image pull, gateway start, cron pin), then Firecrawl unless `SKIP_FIRECRAWL=1`, Mnemosyne unless `SKIP_MNEMOSYNE=1`, Agent-Reach unless `SKIP_AGENT_REACH=1`, Notion only if both `NOTION_*` are set, healthcheck, then snapshot if all four AWS/S3 vars are set. `SKIP_*` is not read on `setup-*`. There is no `SKIP_NOTION`.

## C. Runtime env filter

`build_runtime_env` in `scripts/lib/runtime-env.sh`. Local temp, payload `remote.env`, and runtime `.env` are mode 600.

Always written: `OPENROUTER_API_KEY`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS`, `FIRECRAWL_API_URL` (default `http://127.0.0.1:3002`), `SEARXNG_URL` (default `http://127.0.0.1:8888`), `HERMES_TELEGRAM_DISABLE_FALLBACK_IPS` (default `true`), `TIMEZONE`, `TZ` (default `Asia/Dubai`).

Copied if set: Telegram home and group vars, `GATEWAY_ALLOW_ALL_USERS`, `FIRECRAWL_API_KEY`, `PARALLEL_API_KEY`, `EXA_API_KEY`, voice keys (`VOICE_TOOLS_OPENAI_KEY`, `GROQ_API_KEY`, `ELEVENLABS_API_KEY`), `GITHUB_TOKEN`, and the AWS/S3 set (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`, `S3_BUCKET`, `S3_PREFIX`).

Discord: both token and allowlist non-empty, or no `DISCORD_*` at all. Optional Discord channel vars copy only in that case, including `DISCORD_ALLOW_ALL_USERS` if set.

Notion: both `NOTION_API_KEY` and `NOTION_REPORTS_PARENT_PAGE_ID`, else no `NOTION_*`. Then `NOTION_TOKEN` defaults to the API key, plus optional `NOTION_API_VERSION`, `NOTION_FREELANCE_DB_ID`, `NOTION_ROLE_TEMPLATE_PAGE_ID`.

Never forwarded (locked by `tests/test_runtime_env.py`): `TARGET_*`, `SSH_*`, `SKIP_*`, `REMOTE_DIR`, `ALLOW_LOCAL_TARGET`, `PIN_CRON_FORCE`, `FIRECRAWL_MODE`, `LLM_MODEL`. `FIRECRAWL_MODE` is passed only on the SSH command line for Firecrawl.

`config/config.yaml.example` `terminal.docker_forward_env` is `GITHUB_TOKEN`, `NOTION_API_KEY`, `NOTION_TOKEN`, `NOTION_REPORTS_PARENT_PAGE_ID`. No `AWS_*`. AWS keys still land in the host runtime env. Notion also writes `~/.hermes/notion/env` mode 600 and mounts it into the sandbox because `docker_forward_env` is treated as unreliable (`notion-up.sh`).

`mnemosyne-up.sh` forces `memory.provider=mnemosyne`, forces `memory_enabled` and `user_profile_enabled` false, and forces `model.provider` to `openrouter`. The provider force is not stated in `docs/tools/mnemosyne.md`.

## D. Session-path patch

Telegram session ids contain `:`. `scripts/remote/patch-hermes-docker.sh` rewrites the sandbox directory join in the upstream Docker environment module to use `_sanitize_label_value(task_id)`. Marker is that call. Bare `hermes update` can overwrite the file. Reapplied by `hermes-update.sh`, `bootstrap.sh`, and config-only (`|| true` on config-only). Health reapplies only if the marker is missing, from the copy already on the agent host.

`hermes-update.sh` also refreshes seeds, refreshes Mnemosyne if the side-venv exists, refreshes Agent-Reach if the image or skill exists, refreshes Notion if both keys are in the runtime env, restarts the gateway, and pins cron. `PIN_CRON_FORCE` is not in the runtime env. On the agent host the force path is `PIN_CRON_FORCE=1` when invoking `pin-cron-models.sh`. Pin skips a job whose `model` differs from `model.default` unless force is set (`scripts/lib/pin_decision.py`).

Do not repair a broken `hermes` command with `hermes doctor --fix`. Config-only and bootstrap relink `~/.local/bin/hermes` to the venv binary.

## E. Extensions and snapshot

Registration is a hardcoded `case` in `scripts/deploy.sh` plus a Make target. `extensions/registry.yaml` is not read.

- Firecrawl: `firecrawl/docker-compose.yml` binds SearXNG `127.0.0.1:8888` and the API `127.0.0.1:3002`. Default mode `lite`. The script creates `firecrawl/.env` mode 600 if missing.
- Mnemosyne: side-venv `~/.hermes/.mnemosyne/venv` so an upstream update does not wipe it.
- Agent-Reach: image `hermes-terminal:agent-reach`. Sets `terminal.docker_image`. Forwards `GITHUB_TOKEN` only.
- Notion: `yaml.safe_dump` rewrites all of `config.yaml` when the extension runs. Disables `mcp_servers.notion`.
- Snapshot: custom skills (skip builtins, dotfiles, `README.md`, `*.sha256`), `cron/jobs.json`, `manifest.json`, `--sse AES256`. `head-bucket` only. No public-access check. Empty skill tree does not `--delete` remote skills. Watcher unit `hermes-s3-sync.service`. `skills-push` and `cron-push` refresh the snapshot if `S3_BUCKET` is set, even when other AWS vars are incomplete (then warn).

## F. Tests and publish inventory

`make lint` is `bash -n` on `scripts/**/*.sh`. `make test` is `uv run --no-env-file pytest`. Suite covers runtime env filter, localhost refusal, cron shape, pin/skip, config invariants, gitignore, Makefile contract, skill unpack, dotenv, and the PR comment script. `.github/workflows/pr-checks.yml` runs lint, then test (`if: always()`), then `scripts/ci/pr-comment.mjs`. No deploy, SSH, Docker, or network steps. `notion_cli.py` is not tested in that workflow.

`LICENSE` and `CONTRIBUTING` are absent. `pyproject.toml` has no license field.

A clone does not get `.env`, skill bodies, `cron/jobs.json`, or profile seeds. `.gitignore` excludes those, and `tests/test_gitignore.py` locks it. A clone does inherit the default timezone `Asia/Dubai`, the model pin `xiaomi/mimo-v2.5` in `config/config.yaml.example`, Docker volume paths under `/root/.hermes`, the string "Hassen's full professional CV" in `scripts/remote/install-artifacts.sh`, author examples in `docs/tools/memory-profile.md` and `docs/tasks/large-content-generation.md`, and `user_name: Hassen` in `_bmad` config files. Notion page ids in `skills/**` are gitignored, so a stranger clone does not inherit them. None are in the config example or `.env.sample`.

## G. Skill pipeline (not control-plane FRs)

Long-form work is skills-first: load `editorial-os` plus a genre skill, then `/new`. Stages named in docs: brief, research, outline, draft, verify, publish. Research, draft, and verify use `xiaomi/mimo-v2.5` only in the current docs. `docs/tasks/large-content-generation.md` still has a superseded "stronger model" section and a header that says shipped next to "when ready to implement." Image order in the tutorial task disagrees with `docs/content-generation.md`. Those are skill-catalog defects, not control-plane requirements. The control plane's job is the writable content workspace in the published config, and not wiping it on config push.

## I. CD is not in the tree

As of 2026-10-17 the only deploy origin is the laptop. `TARGET_HOST` is a single value. `.github/workflows/pr-checks.yml` runs lint and test only. FR-24 and FR-25 are requirements for a later change, not a description of current scripts.

The intended gates, once built: pull-request checks stay lint and test. After they succeed, a manual click may deploy the environment sandbox. After merge to master, a separate manual click may deploy prod. Green checks do not deploy. Merge does not deploy. The laptop path remains for an atomic test and is not the recommended path. The word **Sandbox** in this addendum still means the Docker terminal. The PRD's environment sandbox is a second, disposable agent host. Prod is not disposable.

## H. Upstream boundary

Hermes Agent (Nous Research, MIT, docs fetched 2026-10-17) is the runtime: install, gateway process, terminal backends, memory, cron, and `hermes update`. It does not ship a laptop-side control plane, a secret filter, or a VPS provisioner. This repo does not replace that runtime and does not track upstream's other gateways (Slack, WhatsApp, Signal, and the rest) unless a later PRD says so. Telegram long-poll is the default here. Webhook mode is upstream, not this default.
