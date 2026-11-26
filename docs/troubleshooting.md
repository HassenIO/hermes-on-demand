# Troubleshooting

## Deploy: SSH fails

```
Permission denied (publickey)
```

- `ssh-add -l` — key loaded?
- Correct `TARGET_USER` / `TARGET_HOST`?
- `SSH_IDENTITY_FILE` if non-default key
- Test: `ssh -o BatchMode=yes -v "$TARGET_USER@$TARGET_HOST" true`

## Deploy: sudo password required

Bootstrap needs passwordless sudo for apt/Docker/linger, or a one-time interactive fix:

```bash
ssh "$TARGET_USER@$TARGET_HOST"
sudo apt update
# finish any docker install prompts
sudo loginctl enable-linger "$USER"
```

Then from the local machine: `./scripts/deploy.sh` or `--health`.

## `hermes: command not found` on VPS

```bash
export PATH="$HOME/.local/bin:$PATH"
# or re-login after install
source ~/.bashrc
hermes doctor
```

## Gateway refuses to start: container hermes exists

Deploy, bootstrap, and health refuse the host gateway while a container named `hermes` exists. It is the removed Docker gateway runtime, and two gateways would share one `state.db`. Follow [Leaving the old Docker gateway runtime](02-deploy.md#leaving-the-old-docker-gateway-runtime), then re-run `make deploy`.

Read `~/.hermes/logs/gateway.log` and `errors.log`, or `journalctl --user -u hermes-gateway -f`, for gateway errors. From the local machine, `make logs` streams the same journal.

## Gateway running but bot silent

1. Token correct? Regenerate via BotFather if unsure  
2. Your numeric id in `TELEGRAM_ALLOWED_USERS`?  
3. `hermes gateway status` and `journalctl --user -u hermes-gateway -f`  
4. Re-push env: `./scripts/deploy.sh --config-only`  
5. Official: re-run platform setup only if needed — we prefer file-based config

## Bot works in DM, not in groups

See [Telegram — groups](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/telegram):

1. BotFather Group Privacy / admin  
2. Remove and re-add bot after privacy change  
3. Group allowlists  
4. `require_mention` settings  

## Model / empty replies

```bash
hermes doctor
hermes config get model
# model should be claude-opus-5-5 with provider anthropic
hermes auth status anthropic   # logged in
```

- OAuth expired or revoked? `hermes auth refresh anthropic`, or log in again: `hermes auth add anthropic --type oauth --no-browser`.
- Subscription limit hit? `hermes auth list` shows the cooldown; `hermes auth reset anthropic` clears it after the window.
- Model id exact: `claude-opus-5-5` (not the OpenRouter `anthropic/...` form)
- Cron or embeddings failing instead? Those use OpenRouter: check `OPENROUTER_API_KEY` in `~/.hermes/.env`

## Browser logins: vault `Permission denied`

Hermes cannot show a masked password prompt from Telegram or Discord, so save site logins on the VPS, as the same user the gateway runs as:

```bash
hermes vault add
```

If the gateway reports `Permission denied` on `~/.hermes/vault/vault.json.enc`, the vault files belong to another user (left over from the old Docker runtime). Give them back, then reply in the thread:

```bash
sudo chown "$(id -u):$(id -g)" ~/.hermes/vault/vault.json.enc ~/.hermes/vault/vault.key
```

## Docker terminal failures

```bash
docker info
groups   # should include docker (re-login after group add)
hermes config get terminal.backend   # docker
```

### `too many colons` / exit 125 on `docker run`

Telegram session IDs contain `:`. Without our patch, Hermes uses them as host paths in `-v` and Docker fails.

```bash
# From the local machine:
./scripts/deploy.sh --health          # re-applies patch if missing
# Or on VPS:
bash ~/hermes-setup/scripts/remote/patch-hermes-docker.sh
hermes gateway restart
```

After `hermes update`, always use `./scripts/deploy.sh --update` (not bare update).

If the user was just added to `docker`, start a new SSH session or:

```bash
sg docker -c 'hermes gateway restart'
```

## Gateway dies after SSH logout

If the Docker runtime is the writer, logout does not matter: the container uses `restart: unless-stopped`, not linger. Do not `hermes gateway install` or `hermes gateway start` while container `hermes` is up.

On the host-unit path, linger is missing:

```bash
loginctl show-user "$USER" | grep Linger
sudo loginctl enable-linger "$USER"
hermes gateway install
hermes gateway start
```

## Restart loop / flood of Telegram restart messages

Do **not** add custom `ExecStopPost` kill drop-ins. Remove them and reload systemd — see [Messaging gateway — service management](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/).

## Recovery order (upstream)

1. `hermes doctor`  
2. Check `~/.hermes/.env` and `config.yaml`  
3. `hermes gateway status` / restart  
4. `./scripts/deploy.sh --config-only` from the local machine  
5. Official `hermes setup` only as last resort (interactive)
