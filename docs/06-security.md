# Security

## Threat model (short)

Hermes with terminal tools can run commands. On a VPS that means anyone who can message the bot (if allowlist is open) or who steals the bot token can drive those tools. Treat the bot like production SSH access.

## Baseline controls (this repo)

| Control | How |
|---------|-----|
| No Hermes on the local machine | Deploy scripts target `TARGET_HOST` only |
| Telegram allowlist | `TELEGRAM_ALLOWED_USERS` required |
| Secrets not in git | `.env` gitignored; `.env.sample` has empty placeholders |
| Runtime secrets mode | `~/.hermes/.env` chmod `600` |
| Agent sandbox | `terminal.backend: docker` |
| No inbound for chat | Telegram long polling (outbound only) |
| Least surprise | `GATEWAY_ALLOW_ALL_USERS` unset/false |

## SSH

- Key-based auth only; disable password auth on the VPS when possible
- Deploy uses `BatchMode=yes` (no password prompts in automation)
- Do not put SSH private keys inside the Hermes Docker sandbox

## Docker backend

- Prefer not listing API keys in `terminal.docker_forward_env` unless a skill truly needs them inside the sandbox
- Keep Docker socket access limited to the deploy user
- Understand that `docker` group membership is effectively root-equivalent on the host — only trusted users

## Telegram token

- If leaked: BotFather `/revoke`, put new token in `.env`, `--config-only` deploy
- Do not paste tokens into git issues or chat logs

## OpenRouter key

- Restrict or rotate at [openrouter.ai/keys](https://openrouter.ai/keys) if exposed
- Monitor usage on the OpenRouter dashboard

## VPS hardening (recommended extras)

- `ufw default deny incoming` + allow SSH only (or tailscale/wireguard only)
- Automatic security updates (`unattended-upgrades`)
- Separate deploy user (not shared with other apps)
- Regular `hermes update` and OS patches

## What this stack does not do yet

- Secrets manager (1Password/Vault) injection
- Fail2ban / intrusion detection
- Network policies inside Docker beyond defaults
- Webhook mTLS

Add those when your threat model requires them.
