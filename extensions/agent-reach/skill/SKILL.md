---
name: agent-reach
description: Read and search the open web via platform CLIs (YouTube, GitHub, RSS, Exa, Bilibili, Jina). Zero-config channels only.
version: 1.0.0
platforms: [linux]
metadata:
  hermes:
    tags: [web, youtube, github, rss, search, bilibili]
    category: research
    requires_toolsets: [terminal]
---

# Agent Reach (zero-config)

You have shell tools inside the **Docker terminal sandbox** for internet research.
Prefer Hermes built-in **Firecrawl** web tools (`web_search` / `web_extract`) for generic page scrape/search when available.
Use this skill for **platform-specific** access (YouTube subtitles, GitHub, RSS, Exa semantic search, Bilibili, clean Markdown via Jina).

Do **not** ask for cookies or desktop browser logins in v1. Cookie platforms (Twitter, Reddit, XHS, etc.) are not configured.

## When to use

- YouTube: summarize video, extract subtitles/metadata
- GitHub: repo overview, search code/issues (public)
- RSS/Atom: read a feed URL
- Semantic web search: Exa via mcporter (if configured)
- Bilibili: search / video detail
- Any URL → clean Markdown when Firecrawl is unavailable: Jina Reader

## Commands (run via terminal)

### Web page → Markdown

Prefer Hermes **Firecrawl** tools when available. Fallbacks in terminal:

```bash
# Jina Reader (may rate-limit some IPs)
curl -fsSL -A "Mozilla/5.0" "https://r.jina.ai/URL" | head -c 50000

# Plain fetch last resort
curl -fsSL -A "Mozilla/5.0" "URL" | head -c 30000
```

### YouTube (yt-dlp)

```bash
# Metadata JSON
yt-dlp --dump-json --no-download "YOUTUBE_URL" | head -c 100000

# Subtitles / auto-captions (best effort)
yt-dlp --skip-download --write-auto-sub --sub-lang en,en-US --sub-format vtt -o "/tmp/yt.%(ext)s" "YOUTUBE_URL" \
  && cat /tmp/yt*.vtt 2>/dev/null | head -c 80000
```

### GitHub

```bash
# Public API (no token required for public repos)
curl -fsSL -H "Accept: application/vnd.github+json" "https://api.github.com/repos/owner/repo"
curl -fsSL -H "Accept: application/vnd.github.raw" "https://api.github.com/repos/owner/repo/readme"

# gh CLI (works better with GITHUB_TOKEN in env)
gh repo view owner/repo
gh search repos "query" --limit 10
gh issue list -R owner/repo --limit 20
```

### RSS / Atom

```bash
python3 - <<'PY'
import feedparser, sys
url = sys.argv[1]
f = feedparser.parse(url)
print("title:", getattr(f.feed, "title", ""))
for e in f.entries[:15]:
    print("-", getattr(e, "title", ""), "|", getattr(e, "link", ""))
    s = getattr(e, "summary", "") or ""
    print(" ", s[:280].replace("\n", " "))
PY
FEED_URL
```

### Exa semantic search (mcporter)

```bash
mcporter call exa.web_search_exa query="YOUR QUERY" numResults=5
```

If mcporter/Exa is not configured, fall back to Firecrawl `web_search` or Jina on known URLs.

### Bilibili

```bash
bili search "query" --type video 2>/dev/null || bili-cli search "query" 2>/dev/null
```

### Diagnostics

```bash
agent-reach doctor 2>/dev/null || true
yt-dlp --version; gh --version; which mcporter curl python3
```

## Procedure

1. Pick the narrowest tool for the platform (table above).
2. Run via `terminal`. Prefer short outputs; truncate long transcripts.
3. Summarize for the user; cite source URLs.
4. On failure: retry once, then try Firecrawl/Jina fallback for plain URLs.
5. Never store or request social cookies in this skill version.

## Pitfalls

- Server IPs may be rate-limited by some sites — say so and try another channel.
- yt-dlp subtitle languages vary; try `en` then without lang filter.
- Do not install packages with apt/pip in the sandbox unless the user asks (image is pre-baked).
- Prefer `/tmp` for downloads; clean up large files when done.

## Verification

- `yt-dlp --version` and `gh --version` succeed in terminal.
- A sample YouTube URL returns metadata or captions.
- `curl -fsSL https://r.jina.ai/https://example.com` returns Markdown.
