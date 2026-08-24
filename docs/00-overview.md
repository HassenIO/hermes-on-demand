# Overview

This repository is **infrastructure-as-code** for running [Nous Research Hermes Agent](https://hermes-agent.nousresearch.com/) on a remote Ubuntu VPS. Your Mac is the **control plane** only: secrets, config templates, and deploy scripts. Hermes itself is installed and run **only on the VPS**.

## Architecture

```
macOS (this repo)                         Ubuntu VPS
─────────────────                         ──────────
.env (secrets + TARGET_*)    --SSH-->     TARGET_USER home
config/config.yaml.example   --rsync-->   ~/.hermes/config.yaml
scripts/deploy.sh            --runs-->    scripts/remote/bootstrap.sh
                                          hermes gateway (systemd user)
                                           Docker terminal sandbox
                                           Telegram long-poll (outbound)
                                           OpenRouter → xiaomi/mimo-v2.5
                                           Firecrawl-compatible API (:3002 localhost)
```

| Layer | Choice |
|-------|--------|
| OS | Ubuntu 22.04 or 24.04 |
| Install | Official [install.sh](https://hermes-agent.nousresearch.com/docs/getting-started/installation) |
| Process manager | systemd user service + linger |
| Messaging | [Telegram gateway](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/telegram) |
| Model | OpenRouter [`xiaomi/mimo-v2.5`](https://openrouter.ai/xiaomi/mimo-v2.5) |
| Agent shell | Docker backend (isolated from host secrets by default) |
| Web scrape | Local Firecrawl-compatible API ([docs/tools/firecrawl](tools/firecrawl.md)) |

## What lives where

| Path | Machine | Purpose |
|------|---------|---------|
| `.env` | Mac only (gitignored) | Deploy targets + all secrets |
| `~/.hermes/.env` | VPS | Hermes runtime secrets only (no `TARGET_*`) |
| `~/.hermes/config.yaml` | VPS | Model, terminal, non-secret settings |
| `~/.hermes/hermes-agent/` | VPS | Upstream install (managed by Hermes) |
| This git repo | Mac (+ optional copy under `REMOTE_DIR` on VPS) | Source of truth for *your* setup |

## Design rules

1. **Never install Hermes on the Mac** via these scripts. Deploy always targets `TARGET_HOST`.
2. **Secrets in `.env`**, behaviour in `config.yaml` (Hermes official split).
3. **Telegram deny-by-default**: only `TELEGRAM_ALLOWED_USERS` may talk to the bot.
4. **No inbound ports required** for default long-polling Telegram mode.

## Doc map

| Doc | Topic |
|-----|--------|
| [01-prerequisites](01-prerequisites.md) | VPS, SSH, BotFather, OpenRouter |
| [02-deploy](02-deploy.md) | Golden path, Firecrawl, Docker patch, upgrades |
| [03-configuration](03-configuration.md) | Env vars and config.yaml |
| [04-telegram-gateway](04-telegram-gateway.md) | Bot setup and gateway service |
| [05-operations](05-operations.md) | Update, logs, backup |
| [06-security](06-security.md) | Hardening checklist |
| [tools/](tools/README.md) | Optional tool integrations (Firecrawl, …) |
| [troubleshooting](troubleshooting.md) | Common failures |

## Official upstream docs

- [Quickstart](https://hermes-agent.nousresearch.com/docs/getting-started/quickstart)
- [Installation](https://hermes-agent.nousresearch.com/docs/getting-started/installation)
- [Messaging gateway](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/)
- [Telegram](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/telegram)
- [AI providers](https://hermes-agent.nousresearch.com/docs/integrations/providers)
- [Configuration](https://hermes-agent.nousresearch.com/docs/user-guide/configuration)
- [Environment variables](https://hermes-agent.nousresearch.com/docs/reference/environment-variables)
