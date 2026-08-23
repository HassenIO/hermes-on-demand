# Self-hosted Firecrawl (for Hermes web scrape)

Hermes `web_search` / `web_extract` talk to a **Firecrawl-compatible API**.
This repo runs that API **on the VPS** (bound to localhost only) and sets:

```bash
FIRECRAWL_API_URL=http://127.0.0.1:3002
```

```yaml
# ~/.hermes/config.yaml
web:
  backend: firecrawl
```

Official Hermes docs: [Web Search & Extract](https://hermes-agent.nousresearch.com/docs/user-guide/features/web-search).

## Deploy (from Mac)

```bash
./scripts/deploy.sh --firecrawl
```

### Modes

| Mode | How | RAM | What you get |
|------|-----|-----|----------------|
| **lite** (default) | `docker compose up lite` | ~256–384 MB | `/v2/scrape` + `/v2/search` for Hermes |
| **full** | `FIRECRAWL_MODE=full ./scripts/deploy.sh --firecrawl` | **~4 GB+** | Official Firecrawl images |

A ~1.6 GB VPS **cannot** run full Firecrawl (API process is OOM-killed). Lite is the default.

Full mode on a larger host:

```bash
FIRECRAWL_MODE=full ./scripts/deploy.sh --firecrawl
```

Or on the VPS:

```bash
cd ~/hermes-setup/firecrawl
FIRECRAWL_MODE=full bash ../scripts/remote/firecrawl-up.sh
# or:
docker compose --profile full up -d
```

## Repo layout

```
firecrawl/
  docker-compose.yml   # lite (default) + full profile
  lite/                # small Firecrawl-compatible API
  .env.example         # Postgres password for full profile
scripts/remote/firecrawl-up.sh
```

## What lite implements

Compatible with Hermes’s Firecrawl client:

- `GET /v0/health/readiness`
- `POST /v2/scrape` → markdown via readability + markdownify
- `POST /v2/search` → DuckDuckGo results

Not included (Cloud / full OSS only): advanced anti-bot, crawl graphs, screenshots, Fire-engine, etc.

## Ops

```bash
cd ~/hermes-setup/firecrawl
docker compose ps
docker compose logs -f lite
docker compose restart lite
curl -s http://127.0.0.1:3002/v0/health/readiness
```

## Cloud alternative

If you prefer managed Firecrawl instead of self-host:

```bash
# in Mac .env — omit FIRECRAWL_API_URL
FIRECRAWL_API_KEY=fc-...
```

Then `./scripts/deploy.sh --config-only`.
