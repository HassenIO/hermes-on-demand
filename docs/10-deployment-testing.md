# Deployment testing

How to prove a deploy end to end without touching the machine you are on, and without hijacking a bot that is already running.

There is no dry-run. `make deploy` installs packages, Docker, and Hermes on `TARGET_HOST`, sets that host's timezone, starts the gateway, and — if the AWS and S3 variables are set — starts a snapshot watcher. `make health` is the check that comes after, not a substitute for the deploy.

Related: [01-prerequisites](01-prerequisites.md), [02-deploy](02-deploy.md), [troubleshooting](troubleshooting.md).

## Safety rules

- Use a **disposable Ubuntu VPS** (22.04 or 24.04). Do not point a test at the VPS that already serves your bot. A full deploy restarts that gateway and rewrites `~/.hermes/.env` and `config.yaml`.
- Do not point `TARGET_HOST` at this machine. `scripts/deploy.sh` refuses `localhost`, `127.0.0.1`, and `::1` unless `ALLOW_LOCAL_TARGET=1`. Do not set that. `make ssh`, `make skills-push`, and `make cron-push` do not have the same guard. Do not aim those at this machine either.
- Use a **new BotFather token** for the test. One Telegram token can only serve one gateway. If `.env` still has the production token, the new VPS and the old one will fight over the same bot.
- Set `TELEGRAM_ALLOWED_USERS` to your numeric user id (from [@userinfobot](https://t.me/userinfobot)), not an `@username`. Leave `GATEWAY_ALLOW_ALL_USERS` and `DISCORD_ALLOW_ALL_USERS` unset.
- For the first pass, leave `DISCORD_*`, both `NOTION_*`, and the AWS/S3 variables unset. Each of those turns on extra behavior. Add them in the optional section below, one at a time.
- `SKIP_FIRECRAWL=1`, `SKIP_MNEMOSYNE=1`, and `SKIP_AGENT_REACH=1` apply only to full `make deploy`. They do nothing for `make setup-*`.
- Do not run bare `hermes update`. Do not run `hermes doctor --fix` to repair a broken `hermes` command. It can loop `~/.local/bin/hermes`. `make push-config` relinks it.
- Do not commit `.env`. Do not paste tokens into the doc, the commit, or chat.

Default timezone is `Asia/Dubai` unless `TIMEZONE` is set. Deploy applies it on the VPS with `timedatectl`. That is fine on a box you created for this test. It is a surprise on a shared host.

## 1. Local checks (no SSH)

From the repo root, with `.env` filled for the **test** host and the **test** bot:

```bash
make check-env
```

That only tests that `.env` exists. It does not print it, and it does not check that values are filled. Open `.env` yourself and confirm:

| Variable | For this test |
|----------|----------------|
| `TARGET_HOST` | The new VPS, not `localhost`, not the production host |
| `TARGET_USER` | A non-root user with passwordless `sudo` |
| `OPENROUTER_API_KEY` | A key you can afford to use from a test bot |
| `TELEGRAM_BOT_TOKEN` | The new test bot, not the production bot |
| `TELEGRAM_ALLOWED_USERS` | Your numeric id |
| `DISCORD_*`, `NOTION_*`, `AWS_*`, `S3_BUCKET` | Unset |

`make help` lists targets. It does not need `.env`.

## 2. SSH probe

Bootstrap needs a key in the agent and passwordless `sudo` on the VPS. If `sudo` asks for a password, deploy will fail mid-install. Fix that on the VPS before continuing. See [troubleshooting](troubleshooting.md).

```bash
ssh-add -l
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$TARGET_USER@$TARGET_HOST" true
```

`BatchMode=yes` fails instead of prompting. A prompt here means the later deploy will hang or fail. If you use a non-default key or port, match `SSH_IDENTITY_FILE` and `SSH_PORT` from `.env`.

Do not run `make health` on a host that has never been deployed. Health runs the script already at `~/hermes-setup/` and does not upload a new one. On a fresh VPS that directory does not exist yet.

## 3. Full deploy

```bash
make deploy
```

What that does, in order:

1. SSH probe, then sync this repo's payload to `~/hermes-setup/` (`REMOTE_DIR`).
2. Apply timezone (`TIMEZONE`, default `Asia/Dubai`).
3. `bootstrap.sh`: packages, Docker, Hermes (no Playwright), `~/.hermes/.env` mode `600`, `config.yaml`, profile seeds, the Docker colon-path patch, gateway user service with linger, cron model pin.
4. Firecrawl lite on `127.0.0.1:3002`, unless `SKIP_FIRECRAWL=1`.
5. Mnemosyne, unless `SKIP_MNEMOSYNE=1`.
6. Agent-Reach image and skill, unless `SKIP_AGENT_REACH=1`.
7. Notion only if **both** `NOTION_API_KEY` and `NOTION_REPORTS_PARENT_PAGE_ID` are set. With both unset, this step logs a skip. That is the result you want on this pass.
8. Healthcheck.
9. S3 snapshot and watcher only if `S3_BUCKET`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_DEFAULT_REGION` are all set. Leave them unset so a test host does not write to the production bucket.

`TARGET_*` and `SSH_*` stay on this machine. They are not written to `~/.hermes/.env`.

A smaller first boot, still a real deploy:

```bash
SKIP_FIRECRAWL=1 SKIP_MNEMOSYNE=1 SKIP_AGENT_REACH=1 make deploy
```

That still installs Hermes, Docker, the gateway, and the timezone. It does not install the three optional pieces. Bring them up afterwards with `make setup-firecrawl`, `make setup-mnemosyne`, and `make setup-agent-reach` if you want to see each one fail or pass on its own. Those targets ignore `SKIP_*`.

## 4. Health

```bash
make health
```

Health SSHes. It still requires `TARGET_HOST`, `TARGET_USER`, `OPENROUTER_API_KEY`, `TELEGRAM_BOT_TOKEN`, and `TELEGRAM_ALLOWED_USERS` in `.env`. It does not upload a new payload. It can rewrite a broken `~/.local/bin/hermes` symlink and re-apply the colon-path patch if the marker is missing, using the script already on the VPS.

The last line you want is `Healthcheck passed`.

Hard failures (the script exits non-zero):

- `hermes` not on `PATH`
- `docker info` fails
- `~/.hermes/.env` or `config.yaml` missing
- `memories/USER.md` missing or empty
- colon-path patch missing and the re-apply failed
- gateway not running
- Agent-Reach image exists but `yt-dlp` inside it fails

These are warnings. The script can still exit 0:

| Warning | Meaning on a default `make deploy` |
|---------|-------------------------------------|
| Firecrawl not reachable on `:3002` | Failed test, unless you passed `SKIP_FIRECRAWL=1` |
| Mnemosyne side-venv missing, or provider is not `mnemosyne` | Failed test, unless you passed `SKIP_MNEMOSYNE=1` |
| Agent-Reach image or skill missing | Failed test, unless you passed `SKIP_AGENT_REACH=1` |
| `OK  Notion not configured (optional)` | Expected when both `NOTION_*` are unset |
| Notion half-configured | Failed test. Set both vars or neither |
| timezone is not `TIMEZONE` | Failed test. Deploy applies it; health does not |
| `hermes doctor` reported issues | Non-fatal. Read the tail. Do not "fix" it with `hermes doctor --fix` |

Also expect `OK  Docker path sanitize patch` and `OK  gateway status`.

## 5. Telegram

From the account whose numeric id is in `TELEGRAM_ALLOWED_USERS`:

1. Message the test bot.
2. Optional: `/sethome` if you want a home channel for later cron tests.
3. `/new`.
4. Ask something small, for example what it knows about you.

`/new` is what reloads the profile. A reply means the gateway, the allowlist, the OpenRouter key, and the model in `config/config.yaml.example` are working.

If the bot stays silent:

- The token is still attached to another VPS, or `TELEGRAM_ALLOWED_USERS` is not your numeric id.
- On the test VPS: `journalctl --user -u hermes-gateway -f` and `~/.hermes/logs/gateway.log`.
- Do not open inbound ports. Telegram long-poll is outbound.

Then ask it to run a trivial shell command so the Docker sandbox is actually used. A sandbox failure with `too many colons` or exit 125 means the colon-path patch is missing. From this machine, `make health` re-applies it if the marker is missing. If the patch script on the VPS is stale, `make update` or `make push-config` uploads a current one and re-applies it. Do not run bare `hermes update`.

## 6. Optional pieces

Do these only after the default path passes. Put the variables in `.env`, then run the matching target. Each `make setup-*` still syncs the payload and applies timezone even when the piece itself is skipped.

**Discord.** Set both `DISCORD_BOT_TOKEN` and `DISCORD_ALLOWED_USERS`, then `make push-config`. Health should log `OK  Discord env present`. A half pair is not forwarded. Leave `DISCORD_ALLOW_ALL_USERS` unset. Details: [07-discord-gateway](07-discord-gateway.md).

**Notion.** Set both `NOTION_API_KEY` and `NOTION_REPORTS_PARENT_PAGE_ID`, then `make setup-notion`. Health should log `OK  notion-cli me` and `OK  Notion MCP not active`. One var without the other is a failed test. `make setup-notion` with neither var still syncs the payload and applies timezone, then skips the install. That log used to say no VPS changes were made. It does not say that anymore.

**Firecrawl and search.** After `make setup-firecrawl` (or a default deploy), health should show Firecrawl on `127.0.0.1:3002`. Ask the bot to search and to extract one URL. Do not switch the default to `FIRECRAWL_MODE=full` on a small VPS. Do not publish Firecrawl or SearXNG off `127.0.0.1`.

**S3.** Use a private bucket that is not the production bucket, or do not test this on a host whose `.env` already has the production `S3_BUCKET`. `make s3-snapshot` does not create the bucket and does not check that it is private. It mirrors custom skills and `cron/jobs.json` only. Confirm the objects landed, then stop. Details: [09-s3-snapshots](09-s3-snapshots.md).

**Skills and cron.** Only after you mean to change the remote set:

- `make skills-push` mirrors custom skills, prunes remote packages that are missing locally, and excludes `README.md`. If `S3_BUCKET` is set it also snapshots.
- `make skills-pull` replaces local `./skills` (`rsync --delete`). Pull only when the VPS is the copy you want to keep.
- `make cron-push` replaces the remote job set. If `S3_BUCKET` is set it also snapshots. Jobs need a unique `id`, a unique `name`, and a `schedule` object. No tokens in `jobs.json`.
- `make push-config` pins cron jobs to `model.default` except a job that already names a different model. It does not upload `jobs.json`. `PIN_CRON_FORCE` in local `.env` is not forwarded.

## 7. Upgrade path

On the test VPS only, after the smoke test passes:

```bash
make update
make health
```

`make update` runs `hermes update`, then puts the colon-path patch back, refreshes artifacts, restarts the gateway, and pins cron. Then `/new` in Telegram and send one more message. A sandbox `too many colons` after this step means the patch did not survive. That is a failed test.

## After the test

- Revoke the test bot token in BotFather if you are done with it.
- Point `.env` back at the production host before any later `make push-config` or `make deploy`. A forgotten `TARGET_HOST` is how a test deploy lands on the real bot.
- Destroy the test VPS when you no longer need it. It has a copy of the OpenRouter key and the test bot token in `~/.hermes/.env`.
