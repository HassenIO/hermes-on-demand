# Hermes (VPS setup)

Infrastructure-as-code for running [Nous Research Hermes Agent](https://hermes-agent.nousresearch.com/) on an Ubuntu VPS, controlled from your Mac.

| | |
|--|--|
| **Gateway** | Telegram |
| **Model** | Set in `config/config.yaml.example` (OpenRouter) |
| **Agent shell** | Docker backend (path-sanitized for Telegram sessions) |
| **Web** | SearXNG (`web_search`) + Firecrawl lite (`web_extract`) |
| **Memory** | Mnemosyne (default) |
| **Local Mac** | Deploy only — Hermes is **not** installed here |

## Golden path (new VPS)

```bash
cp .env.sample .env
# fill TARGET_HOST, TARGET_USER, OPENROUTER_API_KEY,
#      TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USERS
# optional: TIMEZONE=Asia/Dubai

make deploy
```

That installs Hermes, applies config + profile seeds, patches Docker sandbox paths, starts the gateway, and brings up Firecrawl/SearXNG, Mnemosyne, and Agent-Reach (Notion only if both `NOTION_*` vars are set).

Then in Telegram: message the bot → optional `/sethome` → **`/new`** → chat.

---

## Make commands

Run from the repo root. All targets require a filled `.env`.

### Most used

| Command | What it does |
|---------|----------------|
| **`make deploy`** | Full remote bootstrap / refresh default stack |
| **`make push-config`** | Push secrets + `config.yaml` + artifacts; restart gateway |
| **`make push-artifacts`** | Push SOUL / USER / MEMORY / CV only |
| **`make health`** | Remote healthcheck |
| **`make update`** | `hermes update` + Docker patch + extension refresh |

```bash
make deploy           # after cloning or big stack changes
make push-config      # after editing .env or config/config.yaml.example (e.g. model)
make push-artifacts   # after editing artifacts/*.md
make health           # is the VPS healthy?
make update           # upgrade Hermes on the VPS safely
```

### Setup extensions (on demand)

| Command | What it does |
|---------|----------------|
| **`make setup-firecrawl`** | SearXNG + Firecrawl lite (search + extract) |
| **`make setup-mnemosyne`** | Mnemosyne memory provider (side-venv) |
| **`make setup-agent-reach`** | Custom terminal image + platform web CLIs skill |
| **`make setup-notion`** | Notion REST CLI + skill (*no-op* unless both `NOTION_*` vars are set) |

```bash
make setup-firecrawl
make setup-mnemosyne
make setup-agent-reach
make setup-notion     # only configures when both NOTION_* vars are in .env
```

### Help

```bash
make help         # list targets
make check-env    # confirm .env exists (no secrets printed)
```

Equivalent raw entrypoint (same flags): `./scripts/deploy.sh [--config-only|…]`.

---

## Common workflows

**Change model or terminal settings**

1. Edit `config/config.yaml.example`
2. `make push-config` — also **pins all cron jobs** to the new model (avoids `drift_skip`)
3. Telegram: `/new`

**Update profile / CV**

1. Edit `artifacts/USER.md`, `SOUL.md`, `MEMORY.md`, or `CV.md`
2. `make push-artifacts`
3. Telegram: `/new`

**Rotate secrets (bot token, OpenRouter key)**

1. Edit `.env`
2. `make push-config`

**Enable Notion reports**

1. Follow [docs/tools/notion.md](docs/tools/notion.md)
2. Set **both** `NOTION_API_KEY` and `NOTION_REPORTS_PARENT_PAGE_ID` in `.env`
3. `make setup-notion` (or `make deploy`)

**Skip optional pieces on full deploy**

```bash
SKIP_FIRECRAWL=1 SKIP_MNEMOSYNE=1 SKIP_AGENT_REACH=1 make deploy
```

(Notion is already skipped unless both `NOTION_*` vars are set.)

---

## Documentation

- [Overview](docs/00-overview.md)
- [Prerequisites](docs/01-prerequisites.md)
- [Deploy](docs/02-deploy.md)
- [Configuration](docs/03-configuration.md)
- [Telegram gateway](docs/04-telegram-gateway.md)
- [Operations](docs/05-operations.md)
- [Security](docs/06-security.md)
- [Tools](docs/tools/README.md) — Firecrawl/SearXNG, Mnemosyne, Agent-Reach, Notion, memory profile
- [Troubleshooting](docs/troubleshooting.md)

## Layout

```
Makefile                    # make deploy | push-config | health | setup-*
.env.sample                 # template → copy to .env (gitignored)
artifacts/                  # SOUL, USER, MEMORY, CV → VPS ~/.hermes/
config/config.yaml.example  # model, terminal, web, memory
docs/
extensions/                 # agent-reach, notion, registry
firecrawl/                  # SearXNG + lite API (+ full profile)
scripts/deploy.sh           # Mac entrypoint (used by Make)
scripts/remote/             # bootstrap, patches, extensions, health
```

## Official upstream

- https://hermes-agent.nousresearch.com/docs/
- https://github.com/NousResearch/hermes-agent
