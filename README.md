# Hermes (VPS setup)

Infrastructure-as-code for running [Nous Research Hermes Agent](https://hermes-agent.nousresearch.com/) on an Ubuntu VPS, controlled from your Mac.

| | |
|--|--|
| **Gateway** | Telegram |
| **Model** | OpenRouter [`xiaomi/mimo-v2.5`](https://openrouter.ai/xiaomi/mimo-v2.5) |
| **Agent shell** | Docker backend (path-sanitized for Telegram sessions) |
| **Web scrape** | Firecrawl-compatible API on the VPS (lite by default) |
| **Local Mac** | Deploy only — Hermes is **not** installed here |

## Golden path (new VPS)

```bash
cp .env.sample .env
# fill TARGET_HOST, TARGET_USER, OPENROUTER_API_KEY,
#      TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USERS

./scripts/deploy.sh
```

That single command installs Hermes, applies config + profile seeds, patches Docker sandbox paths, starts the gateway, and brings up Firecrawl lite.

Then in Telegram: message the bot → optional `/sethome` → **`/new`** → chat.

## Commands

```bash
./scripts/deploy.sh              # full stack (Hermes + Firecrawl + Mnemosyne)
./scripts/deploy.sh --config-only
./scripts/deploy.sh --artifacts  # SOUL / USER / MEMORY only
./scripts/deploy.sh --firecrawl  # scrape API only
./scripts/deploy.sh --mnemosyne  # Mnemosyne side-venv + Hermes wrapper
./scripts/deploy.sh --update     # hermes + Mnemosyne upgrade + local fixes
./scripts/deploy.sh --health
SKIP_FIRECRAWL=1 SKIP_MNEMOSYNE=1 ./scripts/deploy.sh
```

## Documentation

- [Overview](docs/00-overview.md)
- [Prerequisites](docs/01-prerequisites.md)
- [Deploy](docs/02-deploy.md) ← golden path + upgrades
- [Configuration](docs/03-configuration.md)
- [Telegram gateway](docs/04-telegram-gateway.md)
- [Operations](docs/05-operations.md)
- [Security](docs/06-security.md)
- [Tools](docs/tools/README.md) — [Firecrawl](docs/tools/firecrawl.md), [Memory profile](docs/tools/memory-profile.md)
- [Troubleshooting](docs/troubleshooting.md)

## Layout

```
.env.sample                 # template → copy to .env (gitignored)
artifacts/SOUL.md           # → VPS ~/.hermes/SOUL.md
artifacts/USER.md           # → VPS ~/.hermes/memories/USER.md  (§ entries)
artifacts/MEMORY.md         # → VPS ~/.hermes/memories/MEMORY.md (§ entries)
config/config.yaml.example  # model + docker terminal + web + memory
docs/
firecrawl/                  # lite (default) + full profile
scripts/deploy.sh           # Mac entrypoint
scripts/remote/             # bootstrap, patches, firecrawl, update, health
```

## Official upstream

- https://hermes-agent.nousresearch.com/docs/
- https://github.com/NousResearch/hermes-agent
