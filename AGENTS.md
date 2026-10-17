<!-- bmad:context -->
<!-- Verified 2026-10-17 against 28be0cb. Managed by bmad-project-context; edits inside this block are replaced on refresh. Keep anything you want preserved outside the markers. -->

## Hermes

Infrastructure-as-code for Nous Research Hermes Agent on an Ubuntu VPS. This checkout is the control plane only. Hermes, the gateway, Docker sandboxes, and Firecrawl run on the VPS. Read `README.md` and the matching page under `docs/` before changing deploy, config, or extensions, and update that page when the workflow changes. Upstream: https://hermes-agent.nousresearch.com/docs/ and https://github.com/NousResearch/hermes-agent.

## Policy

- Never install Hermes, a gateway, or agent sandboxes on this machine. `scripts/deploy.sh` refuses `TARGET_HOST` of `localhost`, `127.0.0.1`, or `::1` unless `ALLOW_LOCAL_TARGET=1`. `skills-push`, `cron-push`, and `make ssh` do not have that guard. Do not point them at this machine either.
- Never commit or print secrets. Placeholders belong in `.env.sample` only. Do not paste tokens, keys, or Notion/Discord IDs into docs, commits, issues, or chat.
- Never put API keys in `config/config.yaml.example`. Secrets are filtered from `.env` into VPS `~/.hermes/.env`. `TARGET_*` and `SSH_*` stay on this machine.
- Never set `GATEWAY_ALLOW_ALL_USERS` or `DISCORD_ALLOW_ALL_USERS` to true. Messaging is deny-by-default. Discord stays off unless both `DISCORD_BOT_TOKEN` and `DISCORD_ALLOWED_USERS` are set.
- Never run bare `hermes update`. It overwrites the Docker colon-path patch and breaks Telegram sandboxes. Use `make update`.
- Never half-configure Notion. Both `NOTION_API_KEY` and `NOTION_REPORTS_PARENT_PAGE_ID` are required, or Notion stays off.
- Do not add `AWS_*` to `terminal.docker_forward_env`. S3 keys must not enter the agent sandbox.
- Do not bake Notion page IDs or other tenant IDs into the repo. They belong in `.env` only.
- Do not run `make deploy`, `full`, `push-config`, `push-artifacts`, `skills-push`, `cron-push`, `update`, `setup-*`, or `s3-snapshot` unless the user asked. Those mutate the VPS. `make health` only when a remote check was asked.
- Do not commit unless the user asked. Do not commit `skills/**`, `cron/**`, or `artifacts/**` except each `README.md`.

## Where things are

- Prefer `make` over raw `./scripts/deploy.sh` flags. `make help` lists targets.
- Remote payload is `~/hermes-setup/` (`REMOTE_DIR`). Runtime is `~/.hermes/`.
- Gateway is the systemd user unit `hermes-gateway`, with linger. Logs: `journalctl --user -u hermes-gateway -f` and `~/.hermes/logs/gateway.log`.
- New extension: follow `extensions/README.md`. Add `extensions/<name>/`, an idempotent `scripts/remote/<name>-up.sh`, a `deploy.sh` flag, an `extensions/registry.yaml` entry, `docs/tools/<name>.md`, and keys in `.env.sample` and `config.yaml.example`. Hook `healthcheck.sh` and `hermes-update.sh` if it must survive `hermes update`.
- Skills catalog: `docs/08-skills.md`. Cron troubleshooting: `skills/productivity/cron-job-troubleshooting`. S3 scope: `docs/09-s3-snapshots.md`.

## Running and verifying

- No test runner and no CI. Check edited scripts with `bash -n`. `make check-env` only tests that `.env` exists and does not print secrets.
- `make health` re-applies `scripts/remote/patch-hermes-docker.sh` only if the colon-path marker is missing, using the copy already on the VPS. It does not upload a new patch.
- Timezone comes from `TIMEZONE` in `.env`, default `Asia/Dubai`. Every deploy mode except `health` applies it. Do not hardcode another zone in scripts.

## Conventions that differ from defaults

- The model lives in `config/config.yaml.example` (`model.default`), not `.env`. Do not set `LLM_MODEL`. Do not pin Sonnet.
- A new runtime var must be added to the `RUNTIME_ENV` filter in `scripts/deploy.sh`, documented in `docs/03-configuration.md`, and placeholdered in `.env.sample`. Then the user runs `make push-config` and `/new`. Do not forward `TARGET_*`, `SSH_*`, `SKIP_*`, or `PIN_CRON_FORCE`. Runtime env files are mode `600`.
- Bash scripts start with `#!/usr/bin/env bash` and `set -euo pipefail`, source `scripts/lib/common.sh`, and use `log`, `warn`, `die`, `load_dotenv`, and `require_vars`, with a `# shellcheck source=...` comment. Local scripts live in `scripts/`. VPS scripts live in `scripts/remote/` and must be idempotent. The header comment says where the script runs. No narration comments.
- New SSH in scripts uses `BatchMode=yes` and `StrictHostKeyChecking=accept-new`. Do not prompt for passwords. `make ssh` is interactive and does not set `BatchMode`.
- Makefile targets need a `##` help comment and `.PHONY`.
- Python only where this tree already has it: `extensions/notion/bin/notion_cli.py`, inline cron checks, and `firecrawl/lite/app.py`. No new app framework.
- Separate `USER.md` and `MEMORY.md` entries with a line containing only `§`. `CV.md` is on demand, not injected every turn. Mnemosyne is the memory store. These files are seeds. Push with `make push-artifacts`, then `/new`. That target also syncs the payload, applies timezone, and restarts the gateway.
- A skill is a directory with `SKILL.md` frontmatter `name`, `description`, and `version`. `make skills-push` mirrors custom skills only, prunes remote packages missing locally, and excludes `README.md`. If `S3_BUCKET` is set it also runs an S3 snapshot. `make skills-pull` replaces local `./skills` with `rsync --delete`. Pull only when the VPS is the source of truth. Builtins are not in this tree. A description change updates the folder `README.md` and `docs/08-skills.md`. Long-form genres load `editorial-os`.
- Cron edits go `make cron-pull`, then `cron/jobs.json`, then `make cron-push`. Pull overwrites the local file. Push replaces the remote set. Jobs need a unique `id`, a unique `name`, and a `schedule` object. No tokens in `jobs.json`. If `S3_BUCKET` is set, push also snapshots to S3. After a model change, fix `drift_skip` with `make push-config`, not by hand-editing the gateway. The same pin runs on `make deploy` and `make update`. It skips a job that already names a different model. `PIN_CRON_FORCE` in local `.env` is not forwarded. On the VPS, run `PIN_CRON_FORCE=1 bash scripts/remote/pin-cron-models.sh`.
- `SKIP_FIRECRAWL=1`, `SKIP_MNEMOSYNE=1`, and `SKIP_AGENT_REACH=1` apply only to full `make deploy`, not to `make setup-*`. Notion is skipped unless both `NOTION_*` vars are set. `make setup-notion` still syncs the payload and applies timezone when Notion itself is skipped.
- S3 is a one-way mirror of custom skills and `cron/jobs.json` only. Not SQLite, sessions, logs, or secrets. The bucket must already exist and be private. The script does not create it or check that it is private.
- Leave `memory_enabled` and `user_profile_enabled` false so seeds are not double-injected. Web search is SearXNG. Extract is Firecrawl. Do not switch the default `FIRECRAWL_MODE` from `lite` to `full`. Keep Firecrawl and SearXNG bound to `127.0.0.1`.
- Telegram session IDs contain `:`. Preserve `scripts/remote/patch-hermes-docker.sh` on every upgrade path. `make update`, bootstrap, and `make push-config` re-apply it. `make health` re-applies it only if the marker is already missing on the VPS.
- No inbound ports for default Telegram long-poll or Discord Gateway. Both are outbound.
- The `docker` group is root-equivalent. Do not widen `docker_forward_env` without a skill that needs the var inside the sandbox.

## Known pitfalls

- Do not run `hermes doctor --fix` to repair a broken `hermes` command. It can loop the `~/.local/bin/hermes` symlink. `make push-config` relinks it.
- The `make setup-notion` log line "no VPS changes made" is false when Notion is skipped. Payload sync and timezone already ran.

<!-- /bmad:context -->
