# Notion reports (Hermes)

Hermes posts durable **reports as child pages** under a fixed parent page in your Notion workspace.

| Piece | Role |
|-------|------|
| Internal integration token | Auth (`NOTION_API_KEY` / `ntn_…`) |
| Parent page | Destination hub (e.g. “Hermes Reports”) |
| MCP | `@notionhq/notion-mcp-server` (stdio via `npx`) |
| Skill | `notion-reports` — when/how to file reports |

Official refs:

- Hermes MCP: https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp  
- Notion integrations: https://www.notion.so/my-integrations  
- Notion MCP server: https://github.com/makenotion/notion-mcp-server  

## One-time Notion console setup

### 1. Create an internal integration

1. Open [My integrations](https://www.notion.so/my-integrations).
2. **New integration** → name e.g. `Hermes VPS`.
3. Associated workspace: your personal/work workspace.
4. **Capabilities** (least privilege for reports):
   - ✅ Read content  
   - ✅ Update content  
   - ✅ Insert content  
   - ❌ Avoid delete unless you need it  
5. **Submit** → copy the **Internal Integration Secret** (`ntn_…` or legacy `secret_…`).

### 2. Create a parent page

1. In Notion, create a page: **Hermes Reports** (or any name).
2. Optionally add a short intro (“Reports filed by Hermes from Telegram”).
3. Open page **⋯ → Connections → Connect to** → select `Hermes VPS`.  
   *If the page is not shared, every API call returns `object_not_found`.*

### 3. Copy the parent page ID

From the browser URL:

```text
https://www.notion.so/Hermes-Reports-a1b2c3d4e5f67890a1b2c3d4e5f67890
                                    └──────────── 32 hex chars ────────────┘
```

Format as UUID (optional dashes):

```text
a1b2c3d4-e5f6-7890-a1b2-c3d4e5f67890
```

Either form works in `NOTION_REPORTS_PARENT_PAGE_ID`.

## Mac `.env`

```bash
NOTION_API_KEY=ntn_your_secret_here
NOTION_REPORTS_PARENT_PAGE_ID=a1b2c3d4-e5f6-7890-a1b2-c3d4e5f67890
# optional
# NOTION_API_VERSION=2022-06-28
# SKIP_NOTION=1
```

Never commit real tokens. `.env` is gitignored.

## Deploy

```bash
# Install / refresh Notion MCP + skill on VPS
./scripts/deploy.sh --notion

# Full bootstrap installs Notion only when NOTION_API_KEY is set
./scripts/deploy.sh

# Opt out on full deploy even if key is present
SKIP_NOTION=1 ./scripts/deploy.sh
```

### What `notion-up.sh` does

1. Requires `NOTION_API_KEY` + `NOTION_REPORTS_PARENT_PAGE_ID` on the VPS  
2. Writes aliases `NOTION_TOKEN` (MCP) into `~/.hermes/.env`  
3. Ensures `npx` / Node are available  
4. Installs skill → `~/.hermes/skills/notion-reports/SKILL.md`  
5. Merges `mcp_servers.notion` into `~/.hermes/config.yaml`  
6. Verifies token + parent page via Notion REST API  
7. Restarts Hermes gateway  

## Hermes config shape

```yaml
# ~/.hermes/config.yaml (merged by installer)
mcp_servers:
  notion:
    command: "npx"
    args: ["-y", "@notionhq/notion-mcp-server"]
    env:
      NOTION_TOKEN: "${NOTION_TOKEN}"
    enabled: true

skills:
  config:
    notion_reports:
      parent_page_id: "a1b2c3d4-e5f6-7890-a1b2-c3d4e5f67890"
```

Gateway process loads `~/.hermes/.env`, so `${NOTION_TOKEN}` resolves at MCP connect time.

## Usage (Telegram)

```text
/new
```

Then:

```text
Research recent MLOps freelance trends in EU remote banking and post a report to Notion.
```

or:

```text
/notion-reports
File a short status report titled "Weekly ops" with today's notes: …
```

Expected:

- New **child page** under the parent  
- Title like `2026-08-25 — Weekly ops`  
- Telegram reply includes the Notion **URL**  

## Report conventions

| Field | Convention |
|-------|------------|
| Title | `YYYY-MM-DD — <short title>` (VPS `TIMEZONE`) |
| Body | Summary → Findings → Sources → Next actions |
| Secrets | Never put API keys or tokens in the page |

## Security

| Practice | Detail |
|----------|--------|
| Scoped share | Connect integration only to the reports parent (and children) |
| Capabilities | Insert + read/update; no delete if possible |
| Secrets | Token only in Mac `.env` → VPS `~/.hermes/.env` (mode 600) |
| Sandbox | MCP runs on the **gateway host**, not inside Docker terminal |
| Chat | Never paste the integration secret into Telegram |

## Ops / health

```bash
./scripts/deploy.sh --health
# On VPS:
grep NOTION_ /root/.hermes/.env | sed 's/=.*/=***/'
ls ~/.hermes/skills/notion-reports/SKILL.md
grep -A12 'notion:' ~/.hermes/config.yaml
```

Token + parent check (VPS):

```bash
set -a; source ~/.hermes/.env; set +a
curl -sS https://api.notion.com/v1/users/me \
  -H "Authorization: Bearer $NOTION_API_KEY" \
  -H "Notion-Version: 2022-06-28"
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `object_not_found` | Share parent page with the integration (Connections) |
| `unauthorized` | Regenerate secret; redeploy `--notion` |
| MCP tools missing | `npx` missing → install node; restart gateway; `/new` |
| Agent invents “no Notion” | `/new` after deploy; confirm skill file exists |
| npx slow first run | First MCP start downloads package; wait or pre-run `npx -y @notionhq/notion-mcp-server --help` |

## Optional later

- Database destination (`NOTION_REPORTS_DATABASE_ID`) with properties  
- Official Notion **remote** MCP + OAuth (better for interactive desktop; awkward on headless VPS)  
- Cron auto-filing digests via Hermes cron + this skill  

## Layout

```
extensions/notion/
  manifest.yaml
  skill/SKILL.md
scripts/remote/notion-up.sh
docs/tools/notion.md
```
