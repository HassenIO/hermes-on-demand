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

On the VPS (SSH):

```bash
hermes update
hermes gateway restart
hermes doctor
```

Or re-run full deploy from Mac after upstream changes if you only manage config from this repo:

```bash
./scripts/deploy.sh --health
```

`hermes update` on a user-service + linger setup can restart the gateway without root. System units may need passwordless sudo for systemctl — see [Messaging gateway — service management](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/).

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
