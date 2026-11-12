# Deploy (local machine → VPS)

Primary path: fill `.env` on the local machine, then run **one** full deploy. Hermes is installed **only on the VPS**. To prove that path on a disposable host, without reusing the production bot token, see [10-deployment-testing](10-deployment-testing.md).

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
4. **Mnemosyne** side-venv + Hermes wrapper plugin (opt out: `SKIP_MNEMOSYNE=1`)
5. **S3 restore** when all four `AWS_*`/`S3_BUCKET` vars are set — pulls custom skills + `cron/jobs.json` back down, only if the host has no job set yet ([09-s3-snapshots](09-s3-snapshots.md))
6. **healthcheck** (re-applies Docker patch if missing after upgrades)

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
./scripts/deploy.sh --mnemosyne     # Mnemosyne side-venv + wrapper only
./scripts/deploy.sh --update        # hermes + Mnemosyne upgrade + re-patch
./scripts/deploy.sh --health        # healthcheck (self-heals Docker patch)
```

## Persona + memory seeds (`artifacts/`)

| Local file | VPS path | Notes |
|------------|----------|--------|
| `artifacts/SOUL.md` | `~/.hermes/SOUL.md` | Agent identity |
| `artifacts/USER.md` | `~/.hermes/memories/USER.md` | User profile (`§`-delimited entries) |
| `artifacts/MEMORY.md` | `~/.hermes/memories/MEMORY.md` | Agent notes (`§`-delimited entries) |
| `artifacts/CV.md` | `~/.hermes/CV.md` | Full CV (on-demand read; mounted into Docker) |

Format details: [tools/memory-profile.md](tools/memory-profile.md).

```bash
# after editing artifacts/
./scripts/deploy.sh --artifacts
# then /new in Telegram
```

## Hermes upgrades (keep our Docker fix)

Upstream `hermes update` can overwrite `docker.py` and re-break Telegram sandboxes.

**From the local machine (preferred):**

```bash
./scripts/deploy.sh --update
```

**On the VPS:**

```bash
bash ~/hermes-setup/scripts/remote/hermes-update.sh
```

The host path runs `hermes update`, re-applies the path sanitize patch, refreshes CLI links, reinstalls artifacts, and restarts the gateway. With `HERMES_DOCKER_RUNTIME=1`, those commands pull `nousresearch/hermes-agent` and recreate the container; they do not run `hermes update`. Healthcheck also re-applies the patch if it is missing. Do not run bare `hermes update` on either path. See [Docker runtime](#docker-runtime-opt-in).

## Docker runtime (opt-in)

Default `make deploy` and `make update` keep the host venv and the `hermes-gateway` user unit. They do not start a container.

Set `HERMES_DOCKER_RUNTIME=1` in the local `.env` (exact `1`; `true` does not count) to run the gateway from `nousresearch/hermes-agent` instead. The flag is not written into `~/.hermes/.env`.

The container bind-mounts the existing host `$HOME/.hermes` directory at `/opt/data`. A fresh root-owned directory with no `state.db` or `sessions/` is given to a non-root `hermes` user before start. A root-owned directory that already has sessions is refused. The image is not given UID 10000. It does not use a named volume, and it does not mount single files (`auth.json`, `.env`, `config.yaml`). `network_mode: host` so loopback Firecrawl (`127.0.0.1:3002`) and SearXNG (`127.0.0.1:8888`) stay reachable. No published ports. Dashboard stays off. No Caddy, DNS, or Open WebUI. Telegram and Discord stay long-poll.

`PUID` and `PGID` are the owner of that directory. The script refuses a root-owned tree. It does not `chown` the tree to UID 10000.

One writer. The up script exits non-zero if `hermes-gateway` is `active`, `activating`, `reloading`, or `deactivating`, if a host `hermes gateway` process is running, or if another container already mounts that directory (running or stopped). It does not stop or disable the unit on that path. Stop the unit yourself, then retry:

```bash
systemctl --user stop hermes-gateway
```

After the container is up, the script disables the user unit so a reboot cannot start it beside `restart: unless-stopped`.

Inside the container, `HOME` and `HERMES_HOME` are `/opt/data`, not `~/.hermes`. A skill or cron line that expands `~/.hermes` looks at `/opt/data/.hermes` and does not see this tree. There is no custom entrypoint to alias it. When the container is started, the host gets a symlink `/opt/data` → `$HOME/.hermes` so terminal-sandbox paths the process builds under `/opt/data` resolve on the host dockerd. Volume sources in `config.yaml` stay host paths.

The host venv is not removed. `/usr/local/lib/hermes-agent` and `~/.hermes/hermes-agent` stay, so you can roll back. Agent-Reach (`.agent-reach/venv`) is a host Python and does not run inside the official image. Mnemosyne (`.mnemosyne/venv`) is different: with the flag set it is built on the image's Python (`python3 -m venv --copies` inside the container) and only runs there. `make setup-mnemosyne` and the CV pointer run its CLI in container `hermes` as the data-dir owner (`run_in_gateway` / `run_mnemosyne` in `scripts/lib/hermes-docker.sh`). Health, the cron pin, and Mnemosyne's `hermes` calls use the gateway's CLI the same way, so they report the container and leave no root-owned files. Leaving the flag unset keeps Mnemosyne on the host venv and the systemd path.

Telegram `docker run` from inside the container is not claimed. The host colon-path patch still runs only when host `docker.py` exists. Image code under `/opt/hermes` is immutable. `make update` with the flag set pulls the image and recreates the container. It does not run `hermes update`.

### Rollback to the host gateway

Stop the container first. Do not start the unit while the container is running.

```bash
docker stop hermes
docker rm hermes
# unlink only; do not use -r. A symlink rm does not delete ~/.hermes.
if [ "$(readlink /opt/data)" = "$HOME/.hermes" ]; then
  rm /opt/data
fi
systemctl --user enable hermes-gateway
hermes gateway start
```

`docker rm` has no `-v`. Do not `docker compose down -v`. Unset `HERMES_DOCKER_RUNTIME` before the next `make deploy`, or deploy will start the container again.

## Docker sandbox notes (small VPS)

- Config uses `container_memory: 768` and `docker_shm_size: 64m` (raise on larger hosts by editing `config/config.yaml.example`).
- Memories dir is mounted read-only into the sandbox.
- Path sanitize: session IDs with `:` become safe directory names under `~/.hermes/sandboxes/docker/`.

## Firecrawl

Default full deploy starts **lite** (fits ~1.5–2 GB RAM). Details: [tools/firecrawl.md](tools/firecrawl.md).

```bash
./scripts/deploy.sh --firecrawl              # re-run / repair
FIRECRAWL_MODE=full ./scripts/deploy.sh --firecrawl  # large hosts only
```

## What is never installed on the local machine

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
