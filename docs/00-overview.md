# Overview

This repository is **infrastructure-as-code** for running [Nous Research Hermes Agent](https://hermes-agent.nousresearch.com/) on a remote Ubuntu VPS. The local machine is the **control plane** only: secrets, config templates, and deploy scripts. Hermes itself is installed and run **only on the VPS**.

## Architecture

```
local machine (this repo)                 Ubuntu VPS
─────────────────────────                 ──────────
.env (secrets + TARGET_*)    --SSH-->     TARGET_USER home
config/config.yaml.example   --rsync-->   ~/.hermes/config.yaml
scripts/deploy.sh            --runs-->    scripts/remote/bootstrap.sh
                                           hermes gateway (systemd user)
                                            Docker terminal sandbox
                                            Telegram long-poll (outbound)
                                            Discord Gateway WS (outbound; optional)
                                            OpenRouter → xiaomi/mimo-v2.5
                                             Firecrawl-compatible API (:3002 localhost)
                                             Agent-Reach terminal image (yt-dlp, gh, …)
```

| Layer | Choice |
|-------|--------|
| OS | Ubuntu 22.04 or 24.04 |
| Install | Official [install.sh](https://hermes-agent.nousresearch.com/docs/getting-started/installation) |
| Process manager | systemd user service + linger |
| Messaging | [Telegram](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/telegram) (default) · [Discord](07-discord-gateway.md) (optional, same gateway) |
| Model | OpenRouter [`xiaomi/mimo-v2.5`](https://openrouter.ai/xiaomi/mimo-v2.5) |
| Agent shell | Docker backend (isolated from host secrets by default) |
| Web scrape | Local Firecrawl-compatible API ([docs/tools/firecrawl](tools/firecrawl.md)) |

## What lives where

| Path | Machine | Purpose |
|------|---------|---------|
| `.env` | Local machine only (gitignored) | Deploy targets + all secrets |
| `~/.hermes/.env` | VPS | Hermes runtime secrets only (no `TARGET_*`) |
| `~/.hermes/config.yaml` | VPS | Model, terminal, non-secret settings |
| `~/.hermes/hermes-agent/` | VPS | Upstream install (managed by Hermes) |
| This git repo | Local machine (+ optional copy under `REMOTE_DIR` on VPS) | Source of truth for *your* setup |

## Design rules

1. **Never install Hermes on the local machine** via these scripts. Deploy always targets `TARGET_HOST`.
2. **Secrets in `.env`**, behaviour in `config.yaml` (Hermes official split).
3. **Messaging deny-by-default**: only allowlisted users may talk to the bot (`TELEGRAM_ALLOWED_USERS`; same rule for Discord when enabled).
4. **No inbound ports required** for default Telegram long-polling or Discord Gateway (both outbound from the VPS).

## Doc map

| Doc | Topic |
|-----|--------|
| [01-prerequisites](01-prerequisites.md) | VPS, SSH, BotFather, OpenRouter |
| [02-deploy](02-deploy.md) | Golden path, Firecrawl, Docker patch, upgrades |
| [03-configuration](03-configuration.md) | Env vars and config.yaml |
| [04-telegram-gateway](04-telegram-gateway.md) | Bot setup and gateway service |
| [05-operations](05-operations.md) | Update, logs, backup |
| [09-s3-snapshots](09-s3-snapshots.md) | Skills + cron mirror to S3 |
| [10-deployment-testing](10-deployment-testing.md) | Disposable VPS end-to-end test |
| [11-testing](11-testing.md) | Local unit tests (`make test`) |
| [06-security](06-security.md) | Hardening checklist |
| [07-discord-gateway](07-discord-gateway.md) | Discord findings, manual prep, Telegram+Discord |
| [tools/](tools/README.md) | Optional tool integrations (Firecrawl, …) |
| [troubleshooting](troubleshooting.md) | Common failures |

## Official upstream docs

- [Quickstart](https://hermes-agent.nousresearch.com/docs/getting-started/quickstart)
- [Installation](https://hermes-agent.nousresearch.com/docs/getting-started/installation)
- [Messaging gateway](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/)
- [Telegram](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/telegram)
- [Discord](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/discord)
- [AI providers](https://hermes-agent.nousresearch.com/docs/integrations/providers)
- [Configuration](https://hermes-agent.nousresearch.com/docs/user-guide/configuration)
- [Environment variables](https://hermes-agent.nousresearch.com/docs/reference/environment-variables)
