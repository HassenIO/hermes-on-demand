"""Minimal Firecrawl-compatible API for Hermes on small VPS hosts.

Implements the subset Hermes calls:
  GET  /v0/health/readiness
  POST /v2/scrape   {url, formats:["markdown"]}
  POST /v2/search   {query, limit}

Not a full Firecrawl substitute (no crawl graph, anti-bot engine, etc.).
"""

from __future__ import annotations

import re
from typing import Any
from urllib.parse import urlparse

import httpx
from bs4 import BeautifulSoup
from fastapi import FastAPI, HTTPException
from markdownify import markdownify as md
from pydantic import BaseModel, Field
from readability import Document

app = FastAPI(title="hermes-firecrawl-lite", version="0.1.0")

_UA = (
    "Mozilla/5.0 (compatible; HermesFirecrawlLite/0.1; "
    "+https://github.com/NousResearch/hermes-agent)"
)
_TIMEOUT = httpx.Timeout(45.0, connect=15.0)


class ScrapeBody(BaseModel):
    url: str
    formats: list[str] = Field(default_factory=lambda: ["markdown"])
    timeout: int | None = None


class SearchBody(BaseModel):
    query: str
    limit: int = 5


def _safe_http_url(url: str) -> str:
    p = urlparse(url)
    if p.scheme not in ("http", "https") or not p.netloc:
        raise HTTPException(status_code=400, detail="url must be http(s)")
    host = (p.hostname or "").lower()
    if host in {"localhost", "127.0.0.1", "0.0.0.0", "::1"} or host.endswith(".local"):
        raise HTTPException(status_code=400, detail="local URLs blocked")
    if re.match(r"^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[0-1])\.)", host):
        raise HTTPException(status_code=400, detail="private network URLs blocked")
    return url


def _html_to_markdown(html: str, base_url: str) -> str:
    try:
        doc = Document(html)
        content = doc.summary(html_partial=True)
        title = (doc.title() or "").strip()
    except Exception:
        content = html
        title = ""
    soup = BeautifulSoup(content, "lxml")
    for tag in soup(["script", "style", "noscript", "iframe"]):
        tag.decompose()
    body = md(str(soup), heading_style="ATX", strip=["img"])
    body = re.sub(r"\n{3,}", "\n\n", body).strip()
    if title and not body.lstrip().startswith("#"):
        return f"# {title}\n\n{body}"
    return body


@app.get("/v0/health/readiness")
def readiness() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/v2/scrape")
async def scrape(body: ScrapeBody) -> dict[str, Any]:
    url = _safe_http_url(body.url.strip())
    async with httpx.AsyncClient(
        timeout=_TIMEOUT,
        follow_redirects=True,
        headers={"User-Agent": _UA, "Accept": "text/html,application/xhtml+xml"},
    ) as client:
        try:
            resp = await client.get(url)
        except httpx.HTTPError as exc:
            raise HTTPException(status_code=502, detail=f"fetch failed: {exc}") from exc

    content_type = (resp.headers.get("content-type") or "").lower()
    text = resp.text
    markdown = ""
    if "html" in content_type or text.lstrip().startswith("<"):
        markdown = _html_to_markdown(text, str(resp.url))
    else:
        markdown = text

    data: dict[str, Any] = {
        "markdown": markdown,
        "metadata": {
            "sourceURL": url,
            "url": str(resp.url),
            "statusCode": resp.status_code,
            "contentType": content_type,
        },
    }
    if "html" in (body.formats or []):
        data["html"] = text
    return {"success": True, "data": data}


@app.post("/v2/search")
async def search(body: SearchBody) -> dict[str, Any]:
    limit = max(1, min(int(body.limit or 5), 20))
    query = (body.query or "").strip()
    if not query:
        raise HTTPException(status_code=400, detail="query required")

    try:
        from duckduckgo_search import DDGS
    except ImportError as exc:
        raise HTTPException(status_code=500, detail="duckduckgo-search missing") from exc

    results: list[dict[str, Any]] = []
    try:
        with DDGS() as ddgs:
            for i, item in enumerate(ddgs.text(query, max_results=limit), start=1):
                results.append(
                    {
                        "title": item.get("title") or "",
                        "url": item.get("href") or item.get("link") or "",
                        "description": item.get("body") or item.get("snippet") or "",
                        "position": i,
                    }
                )
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"search failed: {exc}") from exc

    return {"success": True, "data": {"web": results}}
