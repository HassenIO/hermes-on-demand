# Deploy (Mac → VPS)

Primary path: fill `.env` on your Mac, then run **one** full deploy. Hermes is installed **only on the VPS**.

## Golden path (new VPS)

```bash
cp .env.sample .env
# edit: TARGET_HOST, TARGET_USER, OPENROUTER_API_KEY,
#       TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USERS

ssh-add -l                    # SSH key in agent
./scripts/deploy.sh           # full stack (see below)
```

### What full deploy includes

1. SSH probe + sync repo payload to `REMOTE_DIR` (default `~/hermes-setup`)
2. **bootstrap.sh**
   - apt packages, Docker Engine
   - Official Hermes install with **`--skip-browser`** (no Playwright hang)
   - CLI symlinks to the real venv binary (no self-loop)
   - `~/.hermes/.env` + `config.yaml` from templates
   - **artifacts/** → SOUL.md, memories/USER.md, memories/MEMORY.md
   - **Docker path sanitize patch** (Telegram `:` in session IDs)
   - Gateway user service + linger + start
   - Pre-pull Docker terminal image
3. **Firecrawl lite** on `127.0.0.1:3002` (opt out: `SKIP_FIRECRAWL=1`)
4. **healthcheck** (re-applies Docker patch if missing after upgrades)

### After first deploy (Telegram)

1. Message the bot (allowlisted user only)
2. Optional: `/sethome` for cron / home channel
3. **`/new`** so USER/MEMORY seeds load into a fresh session snapshot
4. Ask: *What do you know about me?*

## Redeploy modes

```bash
./scripts/deploy.sh                 # full bootstrap + Firecrawl lite
SKIP_FIRECRAWL=1 ./scripts/deploy.sh  # full without Firecrawl
./scripts/deploy.sh --config-only   # secrets + config + artifacts + Docker patch
./scripts/deploy.sh --artifacts     # profile files only
./scripts/deploy.sh --firecrawl     # Firecrawl only
./scripts/deploy.sh --update        # hermes update + re-patch + restart
./scripts/deploy.sh --health        # healthcheck (self-heals Docker patch)
```

## Persona + memory seeds (`artifacts/`)

| Local file | VPS path | Notes |
|------------|----------|--------|
| `artifacts/SOUL.md` | `~/.hermes/SOUL.md` | Agent identity |
| `artifacts/USER.md` | `~/.hermes/memories/USER.md` | User profile (`§`-delimited entries) |
| `artifacts/MEMORY.md` | `~/.hermes/memories/MEMORY.md` | Agent notes (`§`-delimited entries) |

Format details: [tools/memory-profile.md](tools/memory-profile.md).

```bash
# after editing artifacts/
./scripts/deploy.sh --artifacts
# then /new in Telegram
```

## Hermes upgrades (keep our Docker fix)

Upstream `hermes update` can overwrite `docker.py` and re-break Telegram sandboxes.

**From Mac (preferred):**

```bash
./scripts/deploy.sh --update
```

**On the VPS:**

```bash
bash ~/hermes-setup/scripts/remote/hermes-update.sh
```

Both run `hermes update`, re-apply the path sanitize patch, refresh CLI links, reinstall artifacts, and restart the gateway. Healthcheck also re-applies the patch if it is missing.

## Docker sandbox notes (small VPS)

- Config uses `container_memory: 512` and `docker_shm_size: 64m` (raise on larger hosts).
- Memories dir is mounted read-only into the sandbox.
- Path sanitize: session IDs with `:` become safe directory names under `~/.hermes/sandboxes/docker/`.

## Firecrawl

Default full deploy starts **lite** (fits ~1.5–2 GB RAM). Details: [tools/firecrawl.md](tools/firecrawl.md).

```bash
./scripts/deploy.sh --firecrawl              # re-run / repair
FIRECRAWL_MODE=full ./scripts/deploy.sh --firecrawl  # large hosts only
```

## What is never installed on the Mac

- Hermes Agent binary / `~/.hermes` runtime
- Gateway systemd units
- Agent Docker sandboxes / Firecrawl containers

Scripts refuse `TARGET_HOST=localhost` unless `ALLOW_LOCAL_TARGET=1`.

## Remote layout after deploy

```
~/hermes-setup/              # deploy payload (REMOTE_DIR)
  scripts/remote/
  config/
  artifacts/
  firecrawl/
  remote.env                 # filtered secrets (not TARGET_*)
~/.hermes/
  .env
  config.yaml
  SOUL.md
  memories/USER.md
  memories/MEMORY.md
  logs/
```

## Sudo on the VPS

Bootstrap may need sudo for apt/Docker/linger. Prefer passwordless sudo for the deploy user, or run as root (`TARGET_USER=root`).
