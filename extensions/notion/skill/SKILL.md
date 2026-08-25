---
name: notion-reports
description: Read and write Notion via notion-cli REST helper (search, find DB, create report pages).
version: 2.0.0
platforms: [linux]
metadata:
  hermes:
    tags: [notion, reports, productivity]
    category: productivity
    requires_toolsets: [terminal]
required_environment_variables:
  - name: NOTION_API_KEY
    prompt: Notion internal integration token (ntn_...)
    help: https://www.notion.so/my-integrations
    required_for: full functionality
  - name: NOTION_REPORTS_PARENT_PAGE_ID
    prompt: Parent page UUID for new reports
    help: Share the page with the integration
    required_for: creating reports
---

# Notion (REST CLI only — no MCP)

Use the host CLI **`notion-cli`** (installed at `~/.hermes/bin/notion-cli`).  
Do **not** use Notion MCP, browser, or web_extract on Notion URLs.

## Binary

```bash
notion-cli me
```

Should be on `PATH` (host: `/usr/local/bin` and `~/.local/bin`; Docker sandbox: `~/.hermes/bin` via mount + `docker_env.PATH`).

Fallback if needed:

```bash
/root/.hermes/bin/notion-cli me
# or
~/.hermes/bin/notion-cli me
```

Credentials: process env, or `~/.hermes/notion/env` (mounted into Docker), or `~/.hermes/.env` on the host.

## Commands

| Command | Use |
|---------|-----|
| `notion-cli me` | Verify token |
| `notion-cli search "query" [--limit 10] [--filter page\|database]` | Search |
| `notion-cli find-db "query"` | Find databases by name |
| `notion-cli get <id>` | Page or database metadata |
| `notion-cli children <page_id>` | Child pages/databases under a page |
| `notion-cli create-report --title "…" --body "…" [--parent ID]` | New child page under reports parent |

All commands print **JSON**. On error, exit non-zero and message on stderr.

## When to use

- Search Notion, find a database/page id, summarize shared content  
- Post a report under `NOTION_REPORTS_PARENT_PAGE_ID`  
- User mentions Job Hunting, freelancing boards, or “in Notion”

## Read procedure (fail-fast)

1. At most **two** CLI calls. Prefer:
   - `notion-cli search "Job Hunting"`
   - `notion-cli find-db "Freelance Opportunities"`  
   or `notion-cli children <job-hunting-page-id>` if you already have the page id.
2. Return **id**, **title**, **url**, **object** from JSON. Do not invent ids.
3. If `count` is 0: say the page/DB is probably **not shared** with the integration (Connections) and **stop**. Do not retry in a loop.
4. Never open `app.notion.com` / `notion.so` with web tools.

## Write procedure (reports)

1. Title: `YYYY-MM-DD — <short title>` (host timezone).  
2. Body: Summary / Findings / Sources / Next actions.  
3. Write body to a temp file if long, then:

```bash
notion-cli create-report --title "2026-08-25 — Weekly" --body-file /tmp/report.md
```

4. Reply with the JSON `url`.

## Pitfalls

- Integration only sees **connected** pages — share each hub (e.g. Job Hunting) via ⋯ → Connections.  
- IDs may be with or without dashes; CLI normalizes.  
- Do not paste tokens into chat or into Notion pages.  
- If `notion-cli` is missing: tell user to run `make setup-notion` on the Mac control plane.

## Verification

```bash
notion-cli me
notion-cli search "test" --limit 3
```
