# Telegram gateway

Official docs: [Messaging gateway](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/) · [Telegram](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/telegram)

## Create the bot

1. [@BotFather](https://t.me/BotFather) → `/newbot`
2. Save the token as `TELEGRAM_BOT_TOKEN`
3. Optional BotFather polish: `/setdescription`, `/setuserpic`, `/setcommands`

Example commands menu:

```
help - Show help
new - Start a new conversation
sethome - Set this chat as home channel
status - Session info
```

## Allowlist (required)

Hermes denies unknown users by default — correct for a bot with terminal tools.

```bash
TELEGRAM_ALLOWED_USERS=123456789
# multiple: 123456789,987654321
```

Get your id from [@userinfobot](https://t.me/userinfobot).

Alternative: DM pairing (`hermes pairing approve telegram CODE`) — see upstream messaging security docs. This repo standardizes on static allowlist via `.env`.

**Never** set `GATEWAY_ALLOW_ALL_USERS=true` on a public VPS with Docker/local tools enabled.

## Gateway process (VPS)

After bootstrap:

```bash
hermes gateway status
hermes gateway start
hermes gateway stop
hermes gateway restart

# logs (user unit)
journalctl --user -u hermes-gateway -f
# or
tail -f ~/.hermes/logs/gateway.log
```

Bootstrap installs a **user** systemd service and enables **linger** so the gateway survives logout and starts at boot without an interactive session:

```bash
hermes gateway install
sudo loginctl enable-linger "$USER"
```

Optional alternative (not default in our scripts): system unit with `sudo hermes gateway install --system`.

## Polling vs webhook

| Mode | When |
|------|------|
| **Long polling (default)** | Always-on VPS — no public URL, no TLS cert. **This repo’s default.** |
| Webhook | Sleepy platforms (Fly/Railway). Needs `TELEGRAM_WEBHOOK_URL` + `TELEGRAM_WEBHOOK_SECRET`. |

You do not need open inbound ports for polling.

## Groups

- Privacy mode ON (BotFather default): bot only sees commands, replies to itself, etc.
- For full group visibility: turn off Group Privacy in BotFather **or** make the bot admin, then remove/re-add the bot to the group.
- Restrict with `TELEGRAM_GROUP_ALLOWED_USERS` / `TELEGRAM_GROUP_ALLOWED_CHATS` as needed.
- Consider `telegram.require_mention: true` in config for noisy groups.

## Home channel

In Telegram after the bot works:

```
/sethome
```

Or set `TELEGRAM_HOME_CHANNEL` / `TELEGRAM_HOME_CHANNEL_NAME` in `.env` and redeploy `--config-only`.

**Multi-platform:** the gateway can also run Discord. There is effectively **one** proactive home for cron/notifications. If you move home to Discord, see [07-discord-gateway](07-discord-gateway.md) (manual prep + cutover notes). Telegram chat can stay enabled as a second surface.

## Useful in-chat commands

| Command | Purpose |
|---------|---------|
| `/new` or `/reset` | Fresh session |
| `/status` | Session info |
| `/model` | Show/switch model (already-configured providers) |
| `/stop` | Cancel current turn |
| `/help` | Help |

Full list: [Messaging gateway — chat commands](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/).
