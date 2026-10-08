# Notion (REST CLI)

Hermes talks to Notion through a **small REST CLI** and the **`notion-reports` skill**.  
**MCP is not used** (avoids long hangs and broken tool-call dumps with flash models).

| Piece | Role |
|-------|------|
| Internal integration token | `NOTION_API_KEY` / `ntn_…` |
| Parent page | Default hub for **new reports** (`NOTION_REPORTS_PARENT_PAGE_ID`) |
| CLI | `~/.hermes/bin/notion-cli` → Notion HTTP API |
| Skill | `notion-reports` — when/how to search and post |

Official: [Notion integrations](https://www.notion.so/my-integrations) · [API](https://developers.notion.com/)

## One-time Notion setup

1. Create an **internal integration** (Read + Insert + Update content).  
2. Copy the secret → `NOTION_API_KEY`.  
3. Create or pick a parent page for reports (e.g. **Hermes Reports**).  
4. **⋯ → Connections → Connect to** your integration (required for every page/DB Hermes should read).  
5. Copy parent page id from the URL into `NOTION_REPORTS_PARENT_PAGE_ID`.

Share **Job Hunting** (and any other hubs) the same way, or search will return empty.

## Local `.env`

**Both variables required** or Notion is never configured:

```bash
NOTION_API_KEY=ntn_...
NOTION_REPORTS_PARENT_PAGE_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

## Deploy

```bash
make setup-notion
# or
./scripts/deploy.sh --notion
```

Full `make deploy` installs Notion only when both vars are set.

### What the installer does

1. No-op unless both env vars are set  
2. Installs `notion-cli` + skill  
3. **Removes/disables** `mcp_servers.notion`  
4. Forwards `NOTION_*` into Docker terminal + mounts `~/.hermes/bin`  
5. Smoke-tests `notion-cli me`  
6. Restarts gateway  

## CLI reference

```bash
notion-cli me
notion-cli search "Job Hunting" --limit 10
notion-cli find-db "Freelance Opportunities"
notion-cli get <page-or-database-id>
notion-cli children <page-id>
notion-cli create-report --title "2026-08-25 — Weekly" --body "..."

# Database (Job Hunt / Freelance Opportunities)
notion-cli db-schema
notion-cli db-query
notion-cli db-create-opp --role "…" --company "…" --location "…" --rate 700 \
  --link "https://…" --summary "…" --why "…"
notion-cli archive <page_id>
```

JSON on stdout. Errors on stderr, non-zero exit.

### Job Hunt IDs

Set these in `.env`. They are not stored in the repo. Deploy forwards them when Notion is enabled; `notion-up.sh` writes them to `~/.hermes/notion/config.env`.

| Env | Purpose |
|-----|---------|
| `NOTION_FREELANCE_DB_ID` | Freelance Opportunities database |
| `NOTION_ROLE_TEMPLATE_PAGE_ID` | “Role Name” template page |

`db-create-opp` creates a DB row and copies the “Role Name” template body with placeholder substitution. Dedupes on Role Name + Company.

## Telegram usage

```text
/new
```

```text
Use notion-cli: search Job Hunting, then find-db Freelance Opportunities and give me the database id.
```

```text
Post a short smoke-test report to Notion titled "CLI smoke".
```

## Why not MCP?

Flash models often stall or print raw `mcp__notion__…` tool XML.  
Direct REST via shell is faster and more reliable on a small VPS.

## Security

- Share only needed pages with the integration  
- Token only in `.env` (never in chat or page body)  
- CLI does not log the token  

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `count: 0` | Connect page/DB to the integration |
| `HTTP 401` | Regenerate token; `make setup-notion` |
| `notion-cli: not found` | `make setup-notion`; sandbox PATH should include `~/.hermes/bin`; host has `/usr/local/bin/notion-cli` |
| Agent still mentions MCP | `/new` after setup; MCP block should be gone |

## Layout

```
extensions/notion/
  bin/notion_cli.py
  skill/SKILL.md
scripts/remote/notion-up.sh
docs/tools/notion.md
```
