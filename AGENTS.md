# Hermes agents instructions

This repo is **infrastructure-as-code** for [Nous Research Hermes Agent](https://hermes-agent.nousresearch.com/) on an Ubuntu VPS. The local machine (this checkout) is the **control plane only**. Hermes, the gateway, Docker sandboxes, and Firecrawl run **only on the VPS**.

Read `README.md` and the matching page under `docs/` before changing deploy, config, or extensions. Upstream: https://hermes-agent.nousresearch.com/docs/ and https://github.com/NousResearch/hermes-agent.

## Hard rules

- Never install Hermes, a gateway, or agent sandboxes on the local machine. Scripts refuse `TARGET_HOST=localhost` unless `ALLOW_LOCAL_TARGET=1`.
- Never commit or print secrets. `.env` is gitignored. Placeholders go in `.env.sample` only. Do not paste tokens, keys, or Notion/Discord IDs into docs, commits, issues, or chat.
- Never put API keys in `config/config.yaml.example`. Secrets live in `.env` and are filtered into VPS `~/.hermes/.env`. `TARGET_*` and `SSH_*` stay on the local machine.
- Never set `GATEWAY_ALLOW_ALL_USERS` or `DISCORD_ALLOW_ALL_USERS` to true. Messaging is deny-by-default.
- Never run bare `hermes update`. It overwrites the Docker colon-path patch and breaks Telegram sandboxes. Use `make update`.
- Never half-configure Notion. Both `NOTION_API_KEY` and `NOTION_REPORTS_PARENT_PAGE_ID` are required, or Notion stays off. Discord needs both `DISCORD_BOT_TOKEN` and `DISCORD_ALLOWED_USERS`.
- Do not add `AWS_*` to `terminal.docker_forward_env`. S3 keys must not enter the agent sandbox.
- Do not bake Notion page IDs or other tenant IDs into the repo. They belong in `.env` only.
- Do not deploy (`make deploy`, `push-config`, `push-artifacts`, `skills-push`, `cron-push`, `update`, `setup-*`, `s3-snapshot`) unless the user asked. Those mutate the VPS.
- Do not commit unless the user asked. Do not commit `skills/**` except `README.md`, `cron/**` except `README.md`, or `artifacts/**` except `README.md`.

## Layout

| Path | Role |
|------|------|
| `Makefile` | User-facing entry. Prefer `make` over raw flags. |
| `scripts/deploy.sh` | Local SSH/rsync entrypoint used by Make. |
| `scripts/lib/common.sh` | `log` / `warn` / `die`, `load_dotenv`, `require_vars`. |
| `scripts/remote/` | Idempotent scripts that run **on the VPS**. |
| `config/config.yaml.example` | Non-secret model, terminal, web, memory. Becomes `~/.hermes/config.yaml`. |
| `.env.sample` | Secret and deploy-var template. Copy to `.env`. |
| `artifacts/` | Profile seeds (gitignored except README). `SOUL.md`, `USER.md`, `MEMORY.md`, `CV.md`. |
| `skills/` | Custom skills (gitignored except READMEs). VPS: `~/.hermes/skills/`. |
| `cron/jobs.json` | Scheduled jobs (gitignored). VPS: `~/.hermes/cron/jobs.json`. |
| `extensions/` | Optional capabilities + `registry.yaml`. |
| `firecrawl/` | SearXNG + Firecrawl lite compose. |
| `docs/` | Source of truth for behavior. Update the matching doc when you change a workflow. |

Remote after deploy: `~/hermes-setup/` (payload, `REMOTE_DIR`) and `~/.hermes/` (runtime). Default timezone `Asia/Dubai`. Model is OpenRouter `xiaomi/mimo-v2.5` in `config.yaml`, not `.env`. Do not pin Sonnet. Do not set `LLM_MODEL`.

## Commands

All targets need a filled `.env`. `make help` lists them.

| Task | Command |
|------|---------|
| Full bootstrap / refresh | `make deploy` |
| Secrets + config + artifacts, restart, pin cron models | `make push-config` |
| Profile seeds only | `make push-artifacts` |
| Health (re-applies Docker patch if missing) | `make health` |
| Safe Hermes upgrade | `make update` |
| SSH to VPS | `make ssh` |
| Skills VPS → local / local → VPS | `make skills-pull` / `make skills-push` |
| Cron VPS → local / local → VPS | `make cron-pull` / `make cron-push` |
| Mirror custom skills + `jobs.json` to S3 | `make s3-snapshot` |
| Extensions | `make setup-firecrawl` `setup-mnemosyne` `setup-agent-reach` `setup-notion` |

Skip optional stack pieces with `SKIP_FIRECRAWL=1`, `SKIP_MNEMOSYNE=1`, `SKIP_AGENT_REACH=1`. Notion is already skipped unless both `NOTION_*` vars are set.

`make push-config` pins cron jobs to `model.default` except jobs that already name a **different** explicit model. It does not upload `jobs.json`. After a local jobs edit, `make cron-push` still. `PIN_CRON_FORCE=1` on the VPS forces every job onto the default.

## Workflows

**Config or model.** Edit `config/config.yaml.example` and/or `.env`. If you add a runtime var, wire it in the `RUNTIME_ENV` filter in `scripts/deploy.sh`, document it in `docs/03-configuration.md`, and add a placeholder to `.env.sample`. Tell the user to `make push-config`, then `/new` in Telegram.

**Profile.** Edit `artifacts/*.md`. `USER.md` and `MEMORY.md` entries are separated by a line containing only `§`. `CV.md` is on-demand, not injected every turn. Mnemosyne is the runtime memory store; these files are seeds. Push with `make push-artifacts`, then `/new`.

**Skills.** A skill is a directory with `SKILL.md` (YAML frontmatter: `name`, `description`, `version`). Edit the local tree. `make skills-push` mirrors custom skills only, **prunes** remote packages missing locally, and **excludes `README.md`**. Pull before editing if the VPS may be newer. Builtin Hermes skills are not in this tree. If the one-line description changes, update the committed folder `README.md` and `docs/08-skills.md`. Long-form genres load `editorial-os`. Catalog: `docs/08-skills.md`.

**Cron.** `make cron-pull`, edit `cron/jobs.json`, `make cron-push`. Push **replaces** the remote set. Jobs need unique `id`, `name`, and a `schedule` object. No tokens in `jobs.json`. Troubleshooting: `skills/productivity/cron-job-troubleshooting`. Drift after a model change is `drift_skip` — pin via `make push-config`, do not hand-edit the gateway.

**New extension.** Follow `extensions/README.md`: `extensions/<name>/`, idempotent `scripts/remote/<name>-up.sh`, a `deploy.sh` flag, registry entry, `docs/tools/<name>.md`, and `.env.sample` / `config.yaml.example` keys. Hook `healthcheck.sh` / `hermes-update.sh` if the feature must survive `hermes update`.

**S3.** One-way mirror of custom skills and `cron/jobs.json` only. Not SQLite, sessions, logs, or secrets. Bucket must already exist and be private. See `docs/09-s3-snapshots.md`.

## Code style

- Bash. `#!/usr/bin/env bash` and `set -euo pipefail`.
- Source `scripts/lib/common.sh`. Use `log`, `warn`, `die`, `load_dotenv`, `require_vars`. Add `# shellcheck source=...`.
- Local scripts live in `scripts/`. VPS scripts live in `scripts/remote/` and must be idempotent.
- SSH uses `BatchMode=yes` and `StrictHostKeyChecking=accept-new`. Do not prompt for passwords.
- Filter secrets in `deploy.sh`. chmod runtime env `600`. Do not forward deploy-only vars to `~/.hermes/.env`.
- Makefile targets need a `##` help comment and `.PHONY`.
- Match existing script style. Header comment saying where the script runs is enough. Do not add narration comments.
- Python only where the tree already uses it (`notion_cli.py`, cron JSON checks). No new app framework.
- There is no test runner. Check with `bash -n` on edited scripts. `make check-env` does not print secrets. `make health` only when the user wants a remote check.

## Stack facts that bite

- Agent shell is Docker (`hermes-terminal:agent-reach`, fallback `nikolaik/python-nodejs`). Small VPS: `container_memory: 768`, Firecrawl **lite** on `127.0.0.1:3002`, SearXNG on `127.0.0.1:8888`. Do not switch the default deploy to Firecrawl full.
- Telegram session IDs contain `:`. `scripts/remote/patch-hermes-docker.sh` sanitizes sandbox paths. Preserve that patch on every upgrade path.
- Web: `web.search_backend: searxng`, `web.extract_backend: firecrawl`. Memory: `provider: mnemosyne`; built-in `memory_enabled` and `user_profile_enabled` are false so seeds are not double-injected.
- Gateway is a systemd **user** service (`hermes-gateway`) with linger. Logs: `journalctl --user -u hermes-gateway -f`, `~/.hermes/logs/`.
- No inbound ports for default Telegram long-poll or Discord Gateway. Both are outbound.
- `docker` group is root-equivalent. Do not widen `docker_forward_env` without a skill that truly needs the var inside the sandbox.

## Docs map

`docs/00-overview.md` architecture · `02-deploy.md` golden path · `03-configuration.md` env vs yaml · `04-telegram-gateway.md` · `05-operations.md` · `06-security.md` · `07-discord-gateway.md` · `08-skills.md` · `09-s3-snapshots.md` · `content-generation.md` · `docs/tools/` · `docs/troubleshooting.md`.
