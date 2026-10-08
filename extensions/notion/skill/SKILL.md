---
name: notion-reports
description: Read/write Notion via notion-cli (search, DB rows, template opp creates, reports).
version: 2.1.0
platforms: [linux]
metadata:
  hermes:
    tags: [notion, reports, freelancing, productivity]
    category: productivity
    requires_toolsets: [terminal]
required_environment_variables:
  - name: NOTION_API_KEY
    prompt: Notion internal integration token (ntn_...)
    help: https://www.notion.so/my-integrations
    required_for: full functionality
  - name: NOTION_REPORTS_PARENT_PAGE_ID
    prompt: Parent page UUID for freeform reports
    help: Share the page with the integration
    required_for: create-report
---

# Notion (REST CLI only — no MCP)

Use **`notion-cli`** only. Do **not** use Notion MCP, browser, or web_extract on Notion URLs.

## Binary

```bash
notion-cli me
```

On PATH via `/usr/local/bin/notion-cli` (host + Docker mount). Fallback: `~/.hermes/bin/notion-cli`.

Credentials: env, or `~/.hermes/notion/env` (mounted into Docker).

## Commands

| Command | Use |
|---------|-----|
| `notion-cli me` | Verify token |
| `notion-cli search "query"` | Search pages/DBs |
| `notion-cli find-db "query"` | Find databases |
| `notion-cli get <id>` | Page or DB metadata |
| `notion-cli children <page_id>` | Child pages/DBs |
| `notion-cli create-report --title "…" --body "…"` | Child page under reports parent |
| `notion-cli db-schema [--database ID]` | DB property schema |
| `notion-cli db-query [--database ID]` | List DB rows (JSON) |
| `notion-cli db-create-opp --role "…" --company "…" …` | New Freelance Opportunities row + template body |
| `notion-cli archive <page_id>` | Archive a page |

## Job Hunt defaults (Freelance Opportunities)

Set in env / `~/.hermes/notion/config.env`. Required for db-query / db-create-opp when `--database` / `--template` are omitted. Not hardcoded.

| Key | Purpose |
|-----|---------|
| `NOTION_FREELANCE_DB_ID` | Freelance Opportunities database |
| `NOTION_ROLE_TEMPLATE_PAGE_ID` | “Role Name” template page |

**Schema (typical):** Role Name (title), Company, Company Location (rich_text), Rate (number), Date (date), Stage (select: New / Applied).

### List opportunities

```bash
notion-cli db-query
```

### Add opportunity (dedupes on Role Name + Company)

```bash
notion-cli db-create-opp \
  --role "Senior MLOps" \
  --company "Acme" \
  --location "Remote EU" \
  --rate 700 \
  --link "https://..." \
  --summary "…" \
  --why "…"
```

Replicates the Role Name template body, substituting `{Company Name}`, `{Role Name}`, `{Role Description}`, `{Rate}`, `{Reason why you should apply}`, `{Link to the opportunity}`, `{Company Location}`.

## Read procedure (fail-fast)

1. Prefer `search` / `find-db` / `db-query` (max 2–3 calls).  
2. Return ids from JSON only.  
3. Empty results → page/DB likely not shared with the integration — stop.  
4. Never scrape `app.notion.com`.

## Freeform reports

```bash
notion-cli create-report --title "2026-08-25 — Weekly" --body-file /tmp/report.md
```

## Pitfalls

- Share every hub (Job Hunting, DBs) with the integration.  
- Prefer `notion-cli` over ad-hoc curl/python helpers.  
- Do not edit bind-mounted `~/.hermes/bin` from inside Docker (read-only); change the Mac repo and `make setup-notion`.  
- Never paste tokens into chat or Notion pages.

## Verification

```bash
notion-cli me
notion-cli db-schema
notion-cli db-query --limit 5
```
