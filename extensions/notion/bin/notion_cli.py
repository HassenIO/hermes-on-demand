#!/usr/bin/env python3
"""Minimal Notion REST CLI for Hermes (no MCP). Stdlib only."""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from typing import Any

DEFAULT_VERSION = "2022-06-28"
API = "https://api.notion.com/v1"
TIMEOUT = 25


def die(msg: str, code: int = 2) -> None:
    print(msg, file=sys.stderr)
    raise SystemExit(code)


def _parse_env_file(path: str) -> None:
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                v = v.strip().strip('"').strip("'")
                if k.startswith("NOTION_") and k not in os.environ:
                    os.environ[k] = v
    except OSError:
        pass


def load_env_files() -> None:
    """Load NOTION_* from hermes env files (host or sandbox mounts)."""
    if os.environ.get("NOTION_API_KEY") or os.environ.get("NOTION_TOKEN"):
        return
    home = os.environ.get("HERMES_HOME") or os.path.expanduser("~/.hermes")
    # Prefer sandbox-safe file (only Notion keys), then full .env
    for path in (
        os.path.join(home, "notion", "env"),
        os.path.join(home, "notion", "config.env"),
        os.path.join(home, ".env"),
    ):
        if os.path.isfile(path):
            _parse_env_file(path)
        if os.environ.get("NOTION_API_KEY") or os.environ.get("NOTION_TOKEN"):
            return


def token() -> str:
    t = os.environ.get("NOTION_TOKEN") or os.environ.get("NOTION_API_KEY") or ""
    if not t:
        die("NOTION_API_KEY (or NOTION_TOKEN) not set", 3)
    return t


def version() -> str:
    return os.environ.get("NOTION_API_VERSION") or DEFAULT_VERSION


def normalize_id(raw: str) -> str:
    s = (raw or "").strip().replace("-", "")
    if len(s) == 32 and all(c in "0123456789abcdefABCDEF" for c in s):
        s = s.lower()
        return f"{s[:8]}-{s[8:12]}-{s[12:16]}-{s[16:20]}-{s[20:]}"
    return raw.strip()


def request(method: str, path: str, body: dict | None = None) -> Any:
    url = path if path.startswith("http") else f"{API}{path}"
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token()}",
            "Notion-Version": version(),
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8", errors="replace")[:800]
        die(f"HTTP {e.code}: {err}", 2)
    except urllib.error.URLError as e:
        die(f"request failed: {e}", 2)


def title_from_props(props: dict) -> str:
    for v in (props or {}).values():
        if not isinstance(v, dict):
            continue
        if v.get("type") == "title":
            parts = v.get("title") or []
            return "".join(p.get("plain_text") or "" for p in parts).strip()
    return ""


def summarize_obj(obj: dict) -> dict:
    otype = obj.get("object") or ""
    oid = obj.get("id") or ""
    title = ""
    if otype == "page":
        title = title_from_props(obj.get("properties") or {})
    elif otype == "database":
        title = title_from_props(obj.get("title") and {"t": {"type": "title", "title": obj.get("title")}} or {})
        if not title and isinstance(obj.get("title"), list):
            title = "".join(p.get("plain_text") or "" for p in obj["title"]).strip()
    parent = obj.get("parent") or {}
    return {
        "object": otype,
        "id": oid,
        "title": title or "(untitled)",
        "url": obj.get("url") or "",
        "parent": parent,
        "archived": obj.get("archived") or obj.get("in_trash") or False,
    }


def cmd_me(_: argparse.Namespace) -> None:
    data = request("GET", "/users/me")
    out = {
        "ok": True,
        "id": data.get("id"),
        "name": data.get("name"),
        "type": data.get("type"),
        "workspace": (data.get("bot") or {}).get("workspace_name"),
    }
    print(json.dumps(out, indent=2))


def cmd_search(args: argparse.Namespace) -> None:
    body: dict[str, Any] = {
        "query": args.query,
        "page_size": max(1, min(int(args.limit), 20)),
    }
    if args.filter in ("page", "database"):
        body["filter"] = {"value": args.filter, "property": "object"}
    data = request("POST", "/search", body)
    results = [summarize_obj(r) for r in (data.get("results") or [])]
    print(json.dumps({"ok": True, "count": len(results), "results": results}, indent=2))


def cmd_get(args: argparse.Namespace) -> None:
    oid = normalize_id(args.id)
    # Try page first, then database
    try:
        data = request("GET", f"/pages/{oid}")
    except SystemExit:
        data = request("GET", f"/databases/{oid}")
    print(json.dumps({"ok": True, **summarize_obj(data), "raw_object": data.get("object")}, indent=2))


def cmd_children(args: argparse.Namespace) -> None:
    oid = normalize_id(args.id)
    data = request(
        "GET",
        f"/blocks/{oid}/children?page_size={max(1, min(int(args.limit), 50))}",
    )
    rows = []
    for b in data.get("results") or []:
        btype = b.get("type") or ""
        entry: dict[str, Any] = {"type": btype, "id": b.get("id")}
        if btype == "child_page":
            entry["title"] = (b.get("child_page") or {}).get("title") or ""
        elif btype == "child_database":
            entry["title"] = (b.get("child_database") or {}).get("title") or ""
        rows.append(entry)
    print(json.dumps({"ok": True, "count": len(rows), "children": rows}, indent=2))


def cmd_find_db(args: argparse.Namespace) -> None:
    body = {
        "query": args.query,
        "page_size": max(1, min(int(args.limit), 20)),
        "filter": {"value": "database", "property": "object"},
    }
    data = request("POST", "/search", body)
    results = [summarize_obj(r) for r in (data.get("results") or [])]
    # Also run unfiltered search and keep database-like objects
    if not results:
        data2 = request(
            "POST",
            "/search",
            {"query": args.query, "page_size": max(1, min(int(args.limit), 20))},
        )
        for r in data2.get("results") or []:
            if r.get("object") in ("database", "data_source"):
                results.append(summarize_obj(r))
    print(json.dumps({"ok": True, "count": len(results), "results": results}, indent=2))


def _paragraph_blocks(text: str) -> list[dict]:
    text = (text or "").strip() or "(empty)"
    chunks: list[str] = []
    buf: list[str] = []
    n = 0
    for line in text.splitlines():
        if n + len(line) + 1 > 1800 and buf:
            chunks.append("\n".join(buf))
            buf, n = [], 0
        buf.append(line)
        n += len(line) + 1
    if buf:
        chunks.append("\n".join(buf))
    blocks = []
    for c in chunks[:100]:
        blocks.append(
            {
                "object": "block",
                "type": "paragraph",
                "paragraph": {
                    "rich_text": [{"type": "text", "text": {"content": c[:2000]}}]
                },
            }
        )
    return blocks


def cmd_create_report(args: argparse.Namespace) -> None:
    parent = normalize_id(
        args.parent
        or os.environ.get("NOTION_REPORTS_PARENT_PAGE_ID")
        or ""
    )
    if not parent:
        die("parent page id required (--parent or NOTION_REPORTS_PARENT_PAGE_ID)", 3)
    body_text = args.body or ""
    if args.body_file:
        with open(args.body_file, encoding="utf-8") as f:
            body_text = f.read()
    title = (args.title or "Hermes report")[:2000]
    payload = {
        "parent": {"page_id": parent},
        "properties": {
            "title": {
                "title": [{"type": "text", "text": {"content": title}}]
            }
        },
        "children": _paragraph_blocks(body_text),
    }
    data = request("POST", "/pages", payload)
    print(
        json.dumps(
            {
                "ok": True,
                "id": data.get("id"),
                "url": data.get("url"),
                "title": title,
            },
            indent=2,
        )
    )


def main() -> None:
    load_env_files()
    p = argparse.ArgumentParser(prog="notion-cli", description="Hermes Notion REST CLI")
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("me", help="Verify token")
    s.set_defaults(func=cmd_me)

    s = sub.add_parser("search", help="Search pages/databases")
    s.add_argument("query")
    s.add_argument("--limit", type=int, default=10)
    s.add_argument("--filter", choices=["page", "database", ""], default="")
    s.set_defaults(func=cmd_search)

    s = sub.add_parser("get", help="Get page or database by id")
    s.add_argument("id")
    s.set_defaults(func=cmd_get)

    s = sub.add_parser("children", help="List block children of a page")
    s.add_argument("id")
    s.add_argument("--limit", type=int, default=30)
    s.set_defaults(func=cmd_children)

    s = sub.add_parser("find-db", help="Find databases by name/query")
    s.add_argument("query")
    s.add_argument("--limit", type=int, default=10)
    s.set_defaults(func=cmd_find_db)

    s = sub.add_parser("create-report", help="Create child page under reports parent")
    s.add_argument("--title", required=True)
    s.add_argument("--body", default="")
    s.add_argument("--body-file", default="")
    s.add_argument("--parent", default="")
    s.set_defaults(func=cmd_create_report)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
