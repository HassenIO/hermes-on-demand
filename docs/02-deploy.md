# Deploy (Mac → VPS)

Primary path: fill `.env` on your Mac, then run the deploy script. Hermes is installed **only on the VPS**.

## First-time deploy

```bash
cp .env.sample .env
# edit .env with real values

ssh-add -l                          # ensure your key is loaded
./scripts/deploy.sh                 # full remote bootstrap
```

What `deploy.sh` does:

1. Validates required `.env` keys
2. Checks SSH (`BatchMode`) to `TARGET_USER@TARGET_HOST`
3. Syncs `scripts/remote/`, config template, and a **filtered** secrets file to `REMOTE_DIR` (default `~/hermes-setup`)
4. Runs `bootstrap.sh` on the VPS:
   - apt packages (`git`, `curl`, `xz-utils`, `ffmpeg`, …)
   - Docker Engine + add user to `docker` group
   - Official Hermes installer if needed
   - Writes `~/.hermes/.env` and `~/.hermes/config.yaml`
   - `hermes gateway install` + enable linger + start
5. Runs remote healthcheck (`hermes doctor`, gateway status)

## After deploy

1. Open Telegram and message your bot
2. You should get a normal agent reply (model banner / tools may appear depending on version)
3. Optional: send `/sethome` in the chat you want for cron delivery
4. Optional: `/status` for session info

## Redeploy modes

```bash
./scripts/deploy.sh                 # full bootstrap (idempotent)
./scripts/deploy.sh --config-only   # push secrets + config.yaml, restart gateway
./scripts/deploy.sh --health        # remote healthcheck only
```

## What is never installed on the Mac

- Hermes Agent binary / `~/.hermes` runtime
- Gateway systemd units
- Docker-backed agent containers for this stack

If you ever want a local Hermes for development, do that outside this repo and prefer a sandboxed backend — these scripts intentionally refuse to target `localhost` unless you override a safety flag (see script comments when implemented).

## Remote layout after deploy

```
~/hermes-setup/           # copy of deploy payload (REMOTE_DIR)
~/.hermes/
  .env                    # runtime secrets only
  config.yaml             # model + terminal
  hermes-agent/           # upstream checkout (installer)
  logs/
  ...
```

## Sudo on the VPS

Bootstrap may need sudo for:

- `apt` packages
- Docker Engine packages
- `loginctl enable-linger`

Prefer passwordless sudo for the deploy user. If sudo prompts for a password, run an interactive SSH session once to finish Docker/linger setup, then re-run `./scripts/deploy.sh --health`.

## Official installer reference

```bash
# This runs on the VPS only (via bootstrap), not on your Mac:
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
```

Docs: [Installation](https://hermes-agent.nousresearch.com/docs/getting-started/installation)
