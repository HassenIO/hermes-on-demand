"""Minimal Firecrawl-compatible API for Hermes on small VPS hosts.

Implements the subset Hermes calls:
  GET  /v0/health/readiness
  POST /v2/scrape   {url, formats:["markdown"]}
  POST /v2/search   {query, limit}

Search uses multiple backends (DDGS → DDG HTML → Brave HTML → Bing HTML)
because DuckDuckGo often blocks datacenter IPs.
"""

from __future__ import annotations

import html as html_lib
import logging
import re
from typing import Any
from urllib.parse import parse_qs, quote_plus, unquote, urlparse

import httpx
from bs4 import BeautifulSoup
from fastapi import FastAPI, HTTPException
from markdownify import markdownify as md
from pydantic import BaseModel, Field
from readability import Document

log = logging.getLogger("firecrawl-lite")
logging.basicConfig(level=logging.INFO)

app = FastAPI(title="hermes-firecrawl-lite", version="0.2.0")

_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
)
_TIMEOUT = httpx.Timeout(45.0, connect=15.0)
_SEARCH_TIMEOUT = httpx.Timeout(25.0, connect=10.0)


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


def _clean_url(href: str) -> str:
    if not href:
        return ""
    href = html_lib.unescape(href.strip())
    # DDG redirect: /l/?uddg=<url>
    if "uddg=" in href:
        try:
            q = parse_qs(urlparse(href).query)
            if "uddg" in q:
                return unquote(q["uddg"][0])
        except Exception:
            pass
    # Bing redirect
    if "bing.com/ck/a" in href and "u=a1" in href:
        try:
            q = parse_qs(urlparse(href).query)
            u = q.get("u", [""])[0]
            if u.startswith("a1"):
                import base64

                pad = "=" * (-len(u[2:]) % 4)
                return base64.urlsafe_b64decode(u[2:] + pad).decode("utf-8", "ignore")
        except Exception:
            pass
    if href.startswith("//"):
        href = "https:" + href
    if not href.startswith("http"):
        return ""
    return href


def _norm_results(raw: list[dict[str, str]], limit: int) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in raw:
        url = _clean_url(item.get("url") or "")
        title = (item.get("title") or "").strip()
        desc = (item.get("description") or "").strip()
        if not url or url in seen:
            continue
        seen.add(url)
        out.append(
            {
                "title": title or url,
                "url": url,
                "description": desc,
                "position": len(out) + 1,
            }
        )
        if len(out) >= limit:
            break
    return out


def _search_ddgs_lib(query: str, limit: int) -> list[dict[str, str]]:
    """Official ddgs / duckduckgo_search package. Prefer non-Bing backends (VPS IPs often get junk)."""
    DDGS = None
    try:
        from ddgs import DDGS as _D  # type: ignore

        DDGS = _D
    except ImportError:
        try:
            from duckduckgo_search import DDGS as _D  # type: ignore

            DDGS = _D
        except ImportError:
            return []

    raw: list[dict[str, str]] = []
    # Explicit backends: skip bing (datacenter IPs often get captcha/garbage ads)
    backends = ("duckduckgo", "google", "yahoo", "mojeek", "wikipedia")

    def _collect(ddgs_obj: Any) -> list[dict[str, str]]:
        out: list[dict[str, str]] = []
        kwargs_list = [
            {"max_results": limit, "backend": ",".join(backends)},
            {"max_results": limit, "backend": "duckduckgo"},
            {"max_results": limit},
        ]
        last_err: Exception | None = None
        for kwargs in kwargs_list:
            try:
                for item in ddgs_obj.text(query, **kwargs):
                    out.append(
                        {
                            "title": item.get("title") or "",
                            "url": item.get("href") or item.get("link") or "",
                            "description": item.get("body") or item.get("snippet") or "",
                        }
                    )
                if out:
                    return out
            except Exception as exc:  # noqa: BLE001
                last_err = exc
                out = []
        if last_err and not out:
            raise last_err
        return out

    try:
        with DDGS() as ddgs:
            raw = _collect(ddgs)
    except TypeError:
        raw = _collect(DDGS())
    return raw


async def _search_searxng(client: httpx.AsyncClient, query: str, limit: int) -> list[dict[str, str]]:
    """Local then public SearXNG instances (JSON API)."""
    import os

    instances: list[str] = []
    local = (os.environ.get("SEARXNG_INTERNAL_URL") or "").rstrip("/")
    if local:
        instances.append(local)
    instances.extend(
        [
            "http://searxng:8080",  # compose service name
            "http://127.0.0.1:8888",
            "https://searx.be",
            "https://searx.tiekoetter.com",
            "https://opnxng.com",
        ]
    )
    # de-dupe preserve order
    seen: set[str] = set()
    instances = [x for x in instances if not (x in seen or seen.add(x))]
    raw: list[dict[str, str]] = []
    for base in instances:
        try:
            resp = await client.get(
                f"{base}/search",
                params={
                    "q": query,
                    "format": "json",
                    "language": "en-US",
                    "categories": "general",
                },
                headers={"User-Agent": _UA, "Accept": "application/json"},
            )
            if resp.status_code != 200:
                continue
            data = resp.json()
            results = data.get("results") or []
            for item in results:
                raw.append(
                    {
                        "title": item.get("title") or "",
                        "url": item.get("url") or item.get("href") or "",
                        "description": item.get("content") or item.get("snippet") or "",
                    }
                )
                if len(raw) >= limit:
                    return raw
            if raw:
                return raw
        except Exception as exc:  # noqa: BLE001
            log.warning("searxng %s failed: %s", base, exc)
            continue
    return raw


async def _search_ddg_html(client: httpx.AsyncClient, query: str, limit: int) -> list[dict[str, str]]:
    url = f"https://html.duckduckgo.com/html/?q={quote_plus(query)}"
    resp = await client.get(
        url,
        headers={
            "User-Agent": _UA,
            "Accept": "text/html",
            "Accept-Language": "en-US,en;q=0.9",
        },
    )
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "lxml")
    raw: list[dict[str, str]] = []
    for res in soup.select("div.result, div.web-result"):
        a = res.select_one("a.result__a")
        if not a:
            continue
        sn = res.select_one("a.result__snippet, td.result__snippet, div.result__snippet")
        raw.append(
            {
                "title": a.get_text(" ", strip=True),
                "url": a.get("href") or "",
                "description": sn.get_text(" ", strip=True) if sn else "",
            }
        )
        if len(raw) >= limit:
            break
    return raw


async def _search_brave_html(client: httpx.AsyncClient, query: str, limit: int) -> list[dict[str, str]]:
    url = f"https://search.brave.com/search?q={quote_plus(query)}&source=web"
    resp = await client.get(
        url,
        headers={
            "User-Agent": _UA,
            "Accept": "text/html",
            "Accept-Language": "en-US,en;q=0.9",
        },
    )
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "lxml")
    raw: list[dict[str, str]] = []
    for res in soup.select("div.snippet[data-type='web'], div.fdb"):
        a = res.select_one("a[href^='http']")
        if not a:
            continue
        title_el = res.select_one("div.title, span.snippet-title, a")
        sn = res.select_one("div.snippet-description, p.snippet-description, div.snippet-content")
        href = a.get("href") or ""
        if "brave.com" in href and "/search" in href:
            continue
        raw.append(
            {
                "title": (title_el.get_text(" ", strip=True) if title_el else "") or a.get_text(" ", strip=True),
                "url": href,
                "description": sn.get_text(" ", strip=True) if sn else "",
            }
        )
        if len(raw) >= limit:
            break
    # Broader fallback selectors
    if not raw:
        for a in soup.select("a[href^='https://']"):
            href = a.get("href") or ""
            if any(x in href for x in ("brave.com", "cloudflare", "microsoft.com/privacy")):
                continue
            title = a.get_text(" ", strip=True)
            if len(title) < 5:
                continue
            raw.append({"title": title, "url": href, "description": ""})
            if len(raw) >= limit:
                break
    return raw


async def _search_bing_html(client: httpx.AsyncClient, query: str, limit: int) -> list[dict[str, str]]:
    url = f"https://www.bing.com/search?q={quote_plus(query)}&setlang=en"
    resp = await client.get(
        url,
        headers={
            "User-Agent": _UA,
            "Accept": "text/html",
            "Accept-Language": "en-US,en;q=0.9",
        },
    )
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "lxml")
    raw: list[dict[str, str]] = []
    for li in soup.select("li.b_algo"):
        a = li.select_one("h2 a")
        if not a:
            continue
        sn = li.select_one("div.b_caption p, p")
        raw.append(
            {
                "title": a.get_text(" ", strip=True),
                "url": a.get("href") or "",
                "description": sn.get_text(" ", strip=True) if sn else "",
            }
        )
        if len(raw) >= limit:
            break
    return raw


async def _search_wikipedia(client: httpx.AsyncClient, query: str, limit: int) -> list[dict[str, str]]:
    """Last-resort structured results (not a full web search)."""
    api = (
        "https://en.wikipedia.org/w/api.php"
        f"?action=opensearch&search={quote_plus(query)}&limit={limit}&namespace=0&format=json"
    )
    resp = await client.get(api, headers={"User-Agent": _UA})
    resp.raise_for_status()
    data = resp.json()
    # [query, [titles], [descs], [urls]]
    titles = data[1] if len(data) > 1 else []
    descs = data[2] if len(data) > 2 else []
    urls = data[3] if len(data) > 3 else []
    raw: list[dict[str, str]] = []
    for i, title in enumerate(titles):
        raw.append(
            {
                "title": title,
                "url": urls[i] if i < len(urls) else "",
                "description": descs[i] if i < len(descs) else "",
            }
        )
    return raw


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

    errors: list[str] = []

    headers = {
        "User-Agent": _UA,
        "Accept": "text/html,application/xhtml+xml,application/json",
        "Accept-Language": "en-US,en;q=0.9",
    }
    async with httpx.AsyncClient(
        timeout=_SEARCH_TIMEOUT,
        follow_redirects=True,
        headers=headers,
    ) as client:
        # Prefer SearXNG JSON (works well from datacenter IPs)
        for name, fn in (
            ("searxng", _search_searxng),
            ("ddg_html", _search_ddg_html),
            ("brave_html", _search_brave_html),
            ("bing_html", _search_bing_html),
            ("wikipedia", _search_wikipedia),
        ):
            try:
                raw = await fn(client, query, limit)
                results = _norm_results(raw, limit)
                if results:
                    log.info("search backend=%s n=%s q=%r", name, len(results), query[:80])
                    return {
                        "success": True,
                        "data": {"web": results, "backend": name},
                    }
                errors.append(f"{name}: empty")
            except Exception as exc:
                errors.append(f"{name}: {exc}")
                log.warning("search %s failed: %s", name, exc)

    # Sync DDGS last (often routes to Bing garbage on VPS)
    try:
        raw = _search_ddgs_lib(query, limit)
        results = _norm_results(raw, limit)
        if results:
            log.info("search backend=ddgs_lib n=%s q=%r", len(results), query[:80])
            return {"success": True, "data": {"web": results, "backend": "ddgs"}}
        errors.append("ddgs_lib: empty")
    except Exception as exc:
        errors.append(f"ddgs_lib: {exc}")
        log.warning("ddgs_lib failed: %s", exc)

    raise HTTPException(
        status_code=502,
        detail="search failed (all backends): " + "; ".join(errors[:8]),
    )
