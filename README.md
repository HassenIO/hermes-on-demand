# Hermes (VPS setup)

Infrastructure-as-code for running [Nous Research Hermes Agent](https://hermes-agent.nousresearch.com/) on an Ubuntu VPS, controlled from your Mac.

| | |
|--|--|
| **Gateway** | Telegram |
| **Model** | OpenRouter [`xiaomi/mimo-v2.5`](https://openrouter.ai/xiaomi/mimo-v2.5) |
| **Agent shell** | Docker backend on the VPS |
| **Web scrape** | Local Firecrawl-compatible API on the VPS |
| **Local Mac** | Deploy only — Hermes is **not** installed here |

## Quick start

```bash
cp .env.sample .env
# fill TARGET_HOST, TARGET_USER, OPENROUTER_API_KEY,
#      TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USERS

./scripts/deploy.sh              # full remote bootstrap over SSH
./scripts/deploy.sh --config-only
./scripts/deploy.sh --health
./scripts/deploy.sh --firecrawl  # local Firecrawl-compatible scrape API for Hermes
```

Hermes is installed **only on the VPS**. This Mac never runs the Hermes installer.

## Documentation

- [Overview](docs/00-overview.md)
- [Prerequisites](docs/01-prerequisites.md) ← start here to collect secrets
- [Deploy](docs/02-deploy.md)
- [Configuration](docs/03-configuration.md)
- [Telegram gateway](docs/04-telegram-gateway.md)
- [Operations](docs/05-operations.md)
- [Security](docs/06-security.md)
- [Tools](docs/tools/README.md) — [Firecrawl](docs/tools/firecrawl.md)
- [Troubleshooting](docs/troubleshooting.md)

## Layout

```
.env.sample                 # template → copy to .env (gitignored)
config/config.yaml.example  # model + docker terminal + web backend
docs/                       # install + ops procedure
docs/tools/                 # per-tool integration docs
firecrawl/                  # self-hosted scrape stack (lite + full)
scripts/                    # deploy automation (Mac → VPS)
```

## Official upstream

- https://hermes-agent.nousresearch.com/docs/
- https://github.com/NousResearch/hermes-agent
