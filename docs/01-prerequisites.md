# Prerequisites

Complete these before the first deploy.

## 1. Ubuntu VPS

- **OS:** Ubuntu 22.04 LTS or 24.04 LTS
- **Access:** SSH as a non-root user with `sudo` (passwordless sudo is ideal for fully unattended bootstrap)
- **Sizing (starting point):** 1–2 vCPU, 2 GB RAM minimum (4 GB more comfortable with Docker sandbox), 20+ GB disk
- **Network:** outbound HTTPS to Telegram, OpenRouter, and package mirrors. No inbound ports required for Telegram long polling.

Create a user if needed (on the VPS as root):

```bash
adduser deploy
usermod -aG sudo deploy
# install your public key in /home/deploy/.ssh/authorized_keys
```

Use that user as `TARGET_USER` in `.env`.

## 2. SSH from the local machine

- Private key loaded in `ssh-agent` (default path used by deploy scripts).
- You can log in non-interactively:

```bash
ssh -o BatchMode=yes "${TARGET_USER}@${TARGET_HOST}" true
```

Optional in `.env`:

- `SSH_PORT` — if not 22
- `SSH_IDENTITY_FILE` — path to a specific key if not using the agent default

## 3. Model: Claude subscription + OpenRouter key

The chat model is `claude-opus-5-5` on provider `anthropic`, pinned in `config/config.yaml.example`. It is **not** in `.env`.

1. After the first deploy, log in to Anthropic once on the VPS with your Claude subscription (OAuth, no API key):

   ```bash
   # Docker runtime (HERMES_DOCKER_RUNTIME=1)
   docker exec -it -u hermes hermes hermes auth add anthropic --type oauth --no-browser
   # Host runtime
   hermes auth add anthropic --type oauth --no-browser
   ```

   The token lands in VPS `~/.hermes/auth.json`. It never goes in `.env` or this repo. Check it with `hermes auth status anthropic` (expect `logged in`).
2. OpenRouter is still required for Mnemosyne embeddings and the auxiliary fallback. Create a key at [openrouter.ai/keys](https://openrouter.ai/keys) and put it in `.env` as `OPENROUTER_API_KEY=`.

Hermes requires models with at least **64k context**. MiMo-V2.5 on OpenRouter exposes a large context window and is suitable.

## 4. Telegram bot

Official guide: [Telegram setup](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/telegram)

1. Open [@BotFather](https://t.me/BotFather) → `/newbot`
2. Choose display name and username (must end in `bot`)
3. Copy the **bot token** → `TELEGRAM_BOT_TOKEN` in `.env`
4. Get your numeric user id from [@userinfobot](https://t.me/userinfobot) → `TELEGRAM_ALLOWED_USERS`
   - Use the number (e.g. `123456789`), not `@username`
   - Multiple users: comma-separated ids

Optional later:

- `/sethome` in a chat after the gateway is up (cron / home channel)
- Group privacy: BotFather → Bot Settings → Group Privacy if you use groups

## 4b. Discord bot (optional, multi-platform)

Discord can run **alongside** Telegram on the same gateway. Complete the **manual** Developer Portal steps, put `DISCORD_*` in `.env`, then `make push-config`.

Full findings, limits, paid-plan answer, and checklist: **[07-discord-gateway](07-discord-gateway.md)**.

Upstream: [Discord setup](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/discord).

Minimum: a **private Discord server**, bot token, bot invited to that server, your Discord user ID, home channel ID. **No Discord Nitro required** for personal/private-server use.

## 5. Local repo setup

```bash
cd /path/to/Hermes
cp .env.sample .env
# edit .env — fill TARGET_HOST, TARGET_USER, OPENROUTER_API_KEY,
#              TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USERS
```

Required variables for first deploy:

| Variable | Example shape |
|----------|----------------|
| `TARGET_HOST` | `203.0.113.10` or `vps.example.com` |
| `TARGET_USER` | `deploy` |
| `OPENROUTER_API_KEY` | `sk-or-...` |
| `TELEGRAM_BOT_TOKEN` | `123456:ABC...` |
| `TELEGRAM_ALLOWED_USERS` | `123456789` |

## 6. Local machine tools

Deploy scripts need:

- `bash`, `ssh`, `scp` or `rsync`
- No Hermes install on the local machine

## Checklist

- [ ] VPS Ubuntu 22.04/24.04 reachable via SSH key
- [ ] `TARGET_HOST` / `TARGET_USER` set
- [ ] OpenRouter key set
- [ ] Telegram bot token + allowed user id set
- [ ] `.env` exists and is **not** committed
