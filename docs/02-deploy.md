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
make sync
# then /new in Telegram
```

Hermes writes to `USER.md` and `MEMORY.md` at runtime.
`./scripts/deploy.sh --artifacts` (`make push-artifacts`) overwrites those edits.
`make sync` runs `scripts/artifacts-sync.sh`, a three-way merge per file, like git.
The merge base is the last synced copy in `.hermes-setup/artifacts/` (gitignored), seeded on first run from `~/hermes-setup/artifacts/` on the VPS.
Remote-only changes are pulled into `artifacts/`, local-only changes are pushed, and changes on both sides go through `git merge-file`.
A conflict leaves git markers in the local file and pushes nothing.
It pushes through `deploy.sh --artifacts` only when a local file differs from the live one, and refuses while conflict markers remain.
`make push-config` and `make update` still reinstall `artifacts/` as is, so run `make sync` first.

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

It runs `hermes update`, re-applies the path sanitize patch, refreshes CLI links, reinstalls artifacts, and restarts the gateway. Healthcheck also re-applies the patch if it is missing. Do not run bare `hermes update`.

## Where things run

Hermes runs on the VPS host, installed by the official installer (`~/.hermes/hermes-agent`, launcher `~/.local/bin/hermes`). The gateway is the `hermes-gateway` systemd user unit, with linger. Mnemosyne is a host side-venv built from the Python that runs Hermes (`hermes --print-runtime-command`).

Docker is used only where it earns its place:

| Piece | Runs in | Why |
|-------|---------|-----|
| Agent terminal sandbox | Docker (`hermes-terminal:agent-reach`) | Agent commands run as root; the container keeps them away from `~/.hermes/.env` and the host |
| Firecrawl lite + SearXNG | Docker compose, loopback only | Small, isolated, and SearXNG has many host dependencies |

`make setup-agent-reach` prunes dangling images and the build cache after a successful build, so rebuilds do not fill the disk.

### Leaving the old Docker gateway runtime

Earlier versions could run the gateway as container `hermes` (`nousresearch/hermes-agent`, `HERMES_DOCKER_RUNTIME=1`). That runtime is gone. Deploy, bootstrap, and health refuse to start the host gateway while that container exists, because two gateways would share one Hermes home. Migrate once, on the VPS:

```bash
docker stop hermes && docker rm hermes        # no -v: data stays in ~/.hermes
# The container ran as another user. sudo reclaims it; id runs as the deploy user.
sudo chown -R "$(id -u):$(id -g)" ~/.hermes
# Back up with no writer running, so each SQLite database and its -wal/-shm agree.
# mktemp creates the file mode 600: the archive holds .env and auth.json.
backup="$(mktemp ~/hermes-backup-$(date +%Y%m%d)-XXXXXX.tgz)"
(cd ~ && tar -czf "$backup" .hermes/state.db* .hermes/config.yaml .hermes/.env .hermes/auth.json \
  .hermes/cron .hermes/memories .hermes/mnemosyne)
# unlink only; do not use -r. A symlink rm does not delete ~/.hermes.
if [ "$(readlink /opt/data)" = "$HOME/.hermes" ]; then sudo rm /opt/data; fi
# Chat routes are keyed by the sessions folder the gateway saw (/opt/data/sessions in
# the container). Rekey them so each Discord or Telegram chat keeps its conversation.
python3 - <<'PY'
import os, sqlite3
db = sqlite3.connect(os.path.expanduser("~/.hermes/state.db"), timeout=30)
with db:
    n = db.execute("update or ignore gateway_routing set scope=? where scope=?",
                   (os.path.realpath(os.path.expanduser("~/.hermes/sessions")), "/opt/data/sessions")).rowcount
print(f"rescoped {n} chat routes")
PY
```

Old local CLI sessions from the container stay readable in history, but the gateway logs `receipt refused: profile_mismatch` for them at start. That is expected: their receipts name the container's home.

Then remove `HERMES_DOCKER_RUNTIME` from the local `.env` and run `make deploy`. It reuses the host install if one is there, rebuilds the Mnemosyne venv (the container's copy does not start on the host), and starts `hermes-gateway`. Free the disk afterwards with `docker rmi nousresearch/hermes-agent`.

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
