# Operations

## Health

From Mac:

```bash
./scripts/deploy.sh --health
```

On VPS:

```bash
export PATH="$HOME/.local/bin:$PATH"
hermes doctor
hermes gateway status
docker info
```

## Logs

```bash
journalctl --user -u hermes-gateway -f
tail -f ~/.hermes/logs/gateway.log
tail -f ~/.hermes/logs/errors.log
```

## Update Hermes

**Do not run bare `hermes update` alone** — it can overwrite our Docker path sanitize and break Telegram sandboxes.

From Mac (preferred):

```bash
./scripts/deploy.sh --update
```

On the VPS:

```bash
bash ~/hermes-setup/scripts/remote/hermes-update.sh
```

That runs `hermes update`, re-applies the Docker colon-path patch, repairs CLI links, refreshes artifacts, and restarts the gateway. Healthcheck also self-heals the patch if missing:

```bash
./scripts/deploy.sh --health
```

## Change model or secrets

1. Edit Mac `.env` and/or `config/config.yaml.example`
2. `./scripts/deploy.sh --config-only`
3. Message the bot or check `hermes gateway status`

## Restart / stop

```bash
hermes gateway restart
hermes gateway stop
hermes gateway start
```

## S3 snapshot (skills + cron)

See [09-s3-snapshots](09-s3-snapshots.md). `make s3-snapshot` uploads custom skills and `jobs.json`, then starts a watcher so later VPS edits sync on their own. SQLite and secrets are not included.

## Backup / move VPS

Upstream supports export/import:

- [FAQ — exporting Hermes](https://hermes-agent.nousresearch.com/docs/reference/faq#exporting-hermes-to-another-machine)
- Prefer `hermes backup` for a full move; profile export alone omits credentials

Also keep your Mac `.env` and this git repo as the recoverable source of secrets + desired config.

## Disk / Docker hygiene

```bash
docker system df
# careful: only prune when you understand impact
# docker system prune
```

Agent sandboxes live under Docker; Hermes state under `~/.hermes/`.

## Cron / scheduled jobs

Once Telegram home is set, use natural-language cron via the agent or upstream cron docs:

- [Cron scheduling](https://hermes-agent.nousresearch.com/docs/user-guide/features/cron)
