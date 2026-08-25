---
name: notion-reports
description: Post research and status reports to Notion as child pages under a configured parent page.
version: 1.0.0
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
    prompt: Parent page UUID for Hermes reports
    help: Share the page with the integration, then copy ID from the URL
    required_for: full functionality
---

# Notion reports

Post durable reports to Notion as **child pages** under a fixed parent page.
Prefer Notion MCP tools (`mcp_notion_*`) when available. Fallback: REST API via curl.

## Config (from environment)

| Variable | Purpose |
|----------|---------|
| `NOTION_API_KEY` | Internal integration token (`ntn_…`) |
| `NOTION_TOKEN` | Alias of the same token (MCP server) |
| `NOTION_REPORTS_PARENT_PAGE_ID` | Parent page UUID (with or without dashes) |
| `NOTION_API_VERSION` | Optional; default `2022-06-28` for REST fallback |

Also check `~/.hermes/notion/config.env` if present (non-secret parent id may be duplicated there).

## When to use

- User asks to “post to Notion”, “file a report”, “save this research in Notion”
- End of a multi-step research / freelancing scan / ops summary that should be archived
- Cron or scheduled digests that should leave a paper trail outside Telegram

Do **not** use for secrets (API keys, tokens, private credentials).

## Report format

**Title:** `YYYY-MM-DD — <short title>` using the host timezone (`TIMEZONE` / Asia/Dubai).

**Body (markdown):**

```markdown
# <title>

## Summary
2–5 sentences.

## Findings
- bullet points with facts and links

## Sources
- URLs used

## Next actions
- optional follow-ups
```

## Procedure (MCP preferred)

1. Confirm env: `NOTION_API_KEY` (or `NOTION_TOKEN`) and `NOTION_REPORTS_PARENT_PAGE_ID`.
2. Load Notion MCP tools if listed (`mcp_notion_*`). Create a **child page** under the parent page id with the title and markdown body.
3. Prefer tools that accept markdown content when available.
4. Return the **public Notion URL** to the user in Telegram.

## Procedure (REST fallback)

If MCP tools are unavailable, use the host terminal (or `execute_code`) with curl.
Normalize page id (strip dashes if needed for some clients; API accepts UUID with dashes):

```bash
# Load secrets from Hermes env if needed
set -a; source ~/.hermes/.env 2>/dev/null; set +a
TOKEN="${NOTION_TOKEN:-$NOTION_API_KEY}"
PARENT="${NOTION_REPORTS_PARENT_PAGE_ID}"
VER="${NOTION_API_VERSION:-2022-06-28}"
TITLE="2026-08-25 — Example report"

# Create child page (title property + paragraph children — keep blocks small)
python3 - <<'PY'
import json, os, urllib.request
token = os.environ["NOTION_TOKEN"] if os.environ.get("NOTION_TOKEN") else os.environ["NOTION_API_KEY"]
parent = os.environ["NOTION_REPORTS_PARENT_PAGE_ID"].replace("-", "")
# Notion accepts IDs with or without hyphens; re-hyphenate if 32 hex
if len(parent) == 32:
    parent = f"{parent[:8]}-{parent[8:12]}-{parent[12:16]}-{parent[16:20]}-{parent[20:]}"
title = os.environ.get("REPORT_TITLE", "Hermes report")
body = os.environ.get("REPORT_BODY", "Empty report.")
# Split body into paragraph chunks ≤1900 chars
paras = []
chunk = []
n = 0
for line in body.splitlines():
    if n + len(line) + 1 > 1800 and chunk:
        paras.append("\n".join(chunk))
        chunk, n = [], 0
    chunk.append(line)
    n += len(line) + 1
if chunk:
    paras.append("\n".join(chunk))
children = []
for p in paras[:100]:
    children.append({
        "object": "block",
        "type": "paragraph",
        "paragraph": {
            "rich_text": [{"type": "text", "text": {"content": p[:2000]}}]
        },
    })
payload = {
    "parent": {"page_id": parent},
    "properties": {
        "title": {"title": [{"type": "text", "text": {"content": title[:2000]}}]}
    },
    "children": children,
}
req = urllib.request.Request(
    "https://api.notion.com/v1/pages",
    data=json.dumps(payload).encode(),
    headers={
        "Authorization": f"Bearer {token}",
        "Notion-Version": os.environ.get("NOTION_API_VERSION", "2022-06-28"),
        "Content-Type": "application/json",
    },
    method="POST",
)
with urllib.request.urlopen(req, timeout=60) as resp:
    data = json.load(resp)
print(data.get("url") or data.get("id"))
PY
```

Set `REPORT_TITLE` and `REPORT_BODY` in the environment before running, or embed them in a one-shot python script written to `/tmp`.

## Pitfalls

- **object_not_found / 404:** Parent page is not shared with the integration (Connections → connect integration).
- **unauthorized:** Wrong/expired token; regenerate internal integration secret.
- **MCP tools missing:** Run `./scripts/deploy.sh --notion` and restart gateway; ensure Node/`npx` on VPS.
- **Huge reports:** Split into multiple pages or trim sources; Notion block limits apply.
- Never paste `NOTION_API_KEY` into chat or into the Notion page body.

## Verification

- After posting, open the returned URL in a browser.
- Parent page “Hermes Reports” shows the new child in Notion sidebar.
