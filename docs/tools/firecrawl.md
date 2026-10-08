# Web search + extract (Firecrawl lite + SearXNG)

Hermes web tools:

| Tool | Backend | Service |
|------|---------|---------|
| `web_search` | **SearXNG** | `http://127.0.0.1:8888` |
| `web_extract` | **Firecrawl lite** | `http://127.0.0.1:3002` |

```bash
# ~/.hermes/.env
FIRECRAWL_API_URL=http://127.0.0.1:3002
SEARXNG_URL=http://127.0.0.1:8888
```

```yaml
# ~/.hermes/config.yaml
web:
  backend: firecrawl
  search_backend: searxng
  extract_backend: firecrawl
```

Official: [Web Search & Extract](https://hermes-agent.nousresearch.com/docs/user-guide/features/web-search).

## Why this split?

On small VPS / datacenter IPs, DuckDuckGo/Bing/Brave HTML often fail or return junk (502 / captcha / ads).  
**Self-hosted SearXNG** aggregates engines from your own container and is what Hermes documents for free reliable search.

## Deploy (from the local machine)

```bash
./scripts/deploy.sh --firecrawl
```

### Modes

| Mode | How | RAM | What you get |
|------|-----|-----|----------------|
| **lite** (default) | SearXNG + firecrawl-lite | ~500–700 MB | search + scrape |
| **full** | `FIRECRAWL_MODE=full …` | **~4 GB+** | Official Firecrawl images |

## Repo layout

```
firecrawl/
  docker-compose.yml   # searxng + lite (+ full profile)
  lite/                # Firecrawl-compatible /v2/scrape (+ /v2/search fallback)
  searxng/settings.yml # JSON API enabled
```

## Ops

```bash
cd ~/hermes-setup/firecrawl
docker compose ps
docker compose logs -f searxng lite

# Search
curl -s "http://127.0.0.1:8888/search?q=hermes+agent&format=json" | head

# Extract
curl -s -X POST http://127.0.0.1:3002/v2/scrape \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com","formats":["markdown"]}'
```

## Browser tool

Hermes `browser_*` needs Chrome/Chromium on the host or a remote browser.  
Not enabled on this VPS by default. Prefer `web_extract` + Agent-Reach for page content.

## Cloud alternative

```bash
# Local .env — managed Firecrawl instead of self-host extract
FIRECRAWL_API_KEY=fc-...
# keep or drop SEARXNG_URL depending on whether you still want local search
```
