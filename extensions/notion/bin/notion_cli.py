#!/usr/bin/env python3
"""Hermes Notion REST CLI (stdlib only). Search, pages, DB rows, template-based creates."""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.request
from typing import Any

DEFAULT_VERSION = "2022-06-28"
API = "https://api.notion.com/v1"
TIMEOUT = 30

# Job Hunt defaults (overridable via env / ~/.hermes/notion/config.env)
DEFAULT_FREELANCE_DB = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
DEFAULT_ROLE_TEMPLATE = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"


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
    home = os.environ.get("HERMES_HOME") or os.path.expanduser("~/.hermes")
    for path in (
        os.path.join(home, "notion", "env"),
        os.path.join(home, "notion", "config.env"),
        os.path.join(home, ".env"),
    ):
        if os.path.isfile(path):
            _parse_env_file(path)


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
    return (raw or "").strip()


def freelance_db_id() -> str:
    return normalize_id(
        os.environ.get("NOTION_FREELANCE_DB_ID") or DEFAULT_FREELANCE_DB
    )


def role_template_id() -> str:
    return normalize_id(
        os.environ.get("NOTION_ROLE_TEMPLATE_PAGE_ID") or DEFAULT_ROLE_TEMPLATE
    )


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
        err = e.read().decode("utf-8", errors="replace")[:1200]
        die(f"HTTP {e.code}: {err}", 2)
    except urllib.error.URLError as e:
        die(f"request failed: {e}", 2)


def title_from_props(props: dict) -> str:
    for v in (props or {}).values():
        if isinstance(v, dict) and v.get("type") == "title":
            parts = v.get("title") or []
            return "".join(p.get("plain_text") or "" for p in parts).strip()
    return ""


def summarize_obj(obj: dict) -> dict:
    otype = obj.get("object") or ""
    oid = obj.get("id") or ""
    title = ""
    if otype == "page":
        title = title_from_props(obj.get("properties") or {})
    elif otype in ("database", "data_source"):
        if isinstance(obj.get("title"), list):
            title = "".join(p.get("plain_text") or "" for p in obj["title"]).strip()
        else:
            title = title_from_props(obj.get("properties") or {})
    return {
        "object": otype,
        "id": oid,
        "title": title or "(untitled)",
        "url": obj.get("url") or "",
        "parent": obj.get("parent") or {},
        "archived": bool(obj.get("archived") or obj.get("in_trash")),
    }


def prop_read(p: dict) -> Any:
    if not isinstance(p, dict):
        return None
    t = p.get("type")
    if t == "title":
        return "".join(x.get("plain_text") or "" for x in (p.get("title") or []))
    if t == "rich_text":
        return "".join(x.get("plain_text") or "" for x in (p.get("rich_text") or []))
    if t in ("url", "email", "phone_number", "number", "checkbox"):
        return p.get(t)
    if t == "select":
        s = p.get("select")
        return s.get("name") if isinstance(s, dict) else None
    if t == "multi_select":
        return [s.get("name") for s in (p.get("multi_select") or []) if isinstance(s, dict)]
    if t == "status":
        s = p.get("status")
        return s.get("name") if isinstance(s, dict) else None
    if t == "date":
        d = p.get("date")
        return d.get("start") if isinstance(d, dict) else None
    return None


def _rt(v: str) -> list[dict]:
    return [{"type": "text", "text": {"content": (v or " ")[:2000]}}]


def schema_map(db_id: str) -> dict:
    obj = request("GET", f"/databases/{normalize_id(db_id)}")
    return dict(obj.get("properties") or {})


def select_options(db_id: str, prop_name: str) -> list[tuple[str, str]]:
    s = schema_map(db_id).get(prop_name) or {}
    opts = (s.get("select") or {}).get("options") or []
    return [(o.get("name") or "", o.get("id") or "") for o in opts]


def prop_write(db_id: str, name: str, value: Any) -> dict | None:
    s = schema_map(db_id).get(name) or {}
    t = s.get("type")
    if value is None or value == "":
        return None
    if t == "title":
        return {"title": [{"type": "text", "text": {"content": str(value)[:2000]}}]}
    if t == "rich_text":
        return {"rich_text": [{"type": "text", "text": {"content": str(value)[:2000]}}]}
    if t == "url":
        v = str(value)
        return {"url": v if v.startswith("http") else "https://" + v}
    if t == "number":
        try:
            cleaned = str(value).replace(",", "").replace("$", "").replace("€", "")
            return {"number": float(cleaned)}
        except (TypeError, ValueError):
            return None
    if t == "date":
        return {"date": {"start": str(value)}}
    if t == "select":
        return {"select": {"name": str(value).strip()}}
    if t == "status":
        return {"status": {"name": str(value).strip()}}
    if t == "checkbox":
        return {"checkbox": bool(value)}
    return {"rich_text": [{"type": "text", "text": {"content": str(value)[:2000]}}]}


def get_block_tree(block_id: str, depth: int = 0, max_depth: int = 6) -> list[dict]:
    data = request("GET", f"/blocks/{normalize_id(block_id)}/children?page_size=100")
    out: list[dict] = []
    text_types = (
        "paragraph",
        "heading_1",
        "heading_2",
        "heading_3",
        "bulleted_list_item",
        "numbered_list_item",
        "to_do",
        "callout",
        "quote",
        "toggle",
        "code",
    )
    for b in data.get("results") or []:
        bt = b.get("type") or ""
        entry: dict[str, Any] = {"type": bt}
        if bt in text_types:
            rts = (b.get(bt) or {}).get("rich_text") or []
            entry["text"] = "".join(x.get("plain_text") or "" for x in rts)
            entry["language"] = (b.get(bt) or {}).get("language")
        if b.get("has_children") and depth < max_depth:
            entry["children"] = get_block_tree(b.get("id") or "", depth + 1, max_depth)
        out.append(entry)
    return out


def plain_block(entry: dict) -> dict:
    bt = entry.get("type") or "paragraph"
    node: dict[str, Any] = {"object": "block", "type": bt}
    txt = entry.get("text") or ""
    if bt in (
        "paragraph",
        "heading_1",
        "heading_2",
        "heading_3",
        "bulleted_list_item",
        "numbered_list_item",
        "to_do",
        "callout",
        "quote",
        "toggle",
    ):
        inner: dict[str, Any] = {"rich_text": _rt(txt) if txt else _rt(" ")}
        if bt == "to_do":
            inner["checked"] = False
        node[bt] = inner
    elif bt == "code":
        node[bt] = {
            "rich_text": _rt(txt or " "),
            "language": entry.get("language") or "plain text",
        }
    elif bt == "divider":
        node[bt] = {}
    else:
        # unsupported → paragraph
        node = {
            "object": "block",
            "type": "paragraph",
            "paragraph": {"rich_text": _rt(txt or " ")},
        }
        bt = "paragraph"
    kids = entry.get("children")
    if kids and bt in node:
        node["children"] = [plain_block(k) for k in kids]
    return node


def build_template_blocks(
    template_id: str,
    subs: dict[str, str],
) -> list[dict]:
    tree = get_block_tree(template_id)
    blocks = []
    text_types = (
        "paragraph",
        "heading_1",
        "heading_2",
        "heading_3",
        "bulleted_list_item",
        "numbered_list_item",
        "to_do",
        "callout",
        "quote",
        "toggle",
        "code",
    )
    for entry in tree:
        node = plain_block(entry)
        bt = node.get("type")
        if bt in text_types and bt in node:
            lines = []
            for rt in node[bt].get("rich_text") or []:
                txt = (rt.get("text") or {}).get("content") or ""
                for k, v in subs.items():
                    txt = txt.replace(k, str(v if v is not None else ""))
                lines.append({"type": "text", "text": {"content": txt[:2000] or " "}})
            node[bt]["rich_text"] = lines
        blocks.append(node)
    return blocks


def query_rows(db_id: str, page_size: int = 100) -> list[dict]:
    data = request(
        "POST",
        f"/databases/{normalize_id(db_id)}/query",
        {"page_size": max(1, min(page_size, 100))},
    )
    rows = []
    for r in data.get("results") or []:
        props = r.get("properties") or {}
        rows.append(
            {
                "id": r.get("id"),
                "url": r.get("url"),
                "props": {k: prop_read(v) for k, v in props.items()},
            }
        )
    return rows


def norm(s: Any) -> str:
    return (str(s) if s is not None else "").strip().lower()


# ── commands ──────────────────────────────────────────────────────────


def cmd_me(_: argparse.Namespace) -> None:
    data = request("GET", "/users/me")
    print(
        json.dumps(
            {
                "ok": True,
                "id": data.get("id"),
                "name": data.get("name"),
                "type": data.get("type"),
                "workspace": (data.get("bot") or {}).get("workspace_name"),
            },
            indent=2,
        )
    )


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
    try:
        data = request("GET", f"/pages/{oid}")
    except SystemExit:
        data = request("GET", f"/databases/{oid}")
    print(
        json.dumps(
            {"ok": True, **summarize_obj(data), "raw_object": data.get("object")},
            indent=2,
        )
    )


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
    return [
        {
            "object": "block",
            "type": "paragraph",
            "paragraph": {
                "rich_text": [{"type": "text", "text": {"content": c[:2000]}}]
            },
        }
        for c in chunks[:100]
    ]


def cmd_create_report(args: argparse.Namespace) -> None:
    parent = normalize_id(
        args.parent or os.environ.get("NOTION_REPORTS_PARENT_PAGE_ID") or ""
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
            "title": {"title": [{"type": "text", "text": {"content": title}}]}
        },
        "children": _paragraph_blocks(body_text),
    }
    data = request("POST", "/pages", payload)
    print(
        json.dumps(
            {"ok": True, "id": data.get("id"), "url": data.get("url"), "title": title},
            indent=2,
        )
    )


def cmd_db_schema(args: argparse.Namespace) -> None:
    db_id = normalize_id(args.database or freelance_db_id())
    s = schema_map(db_id)
    out = {}
    for k, v in s.items():
        entry: dict[str, Any] = {"type": v.get("type")}
        if v.get("type") == "select":
            entry["options"] = [
                o.get("name") for o in (v.get("select") or {}).get("options") or []
            ]
        if v.get("type") == "status":
            entry["options"] = [
                o.get("name") for o in (v.get("status") or {}).get("options") or []
            ]
        out[k] = entry
    print(json.dumps({"ok": True, "database_id": db_id, "properties": out}, indent=2))


def cmd_db_query(args: argparse.Namespace) -> None:
    db_id = normalize_id(args.database or freelance_db_id())
    rows = query_rows(db_id, page_size=int(args.limit))
    if args.raw:
        print(json.dumps({"ok": True, "count": len(rows), "rows": rows}, indent=2))
        return
    # compact table for agent readability
    lines = []
    for r in rows:
        p = r["props"]
        lines.append(
            {
                "id": r["id"],
                "url": r.get("url"),
                "Role Name": p.get("Role Name"),
                "Company": p.get("Company"),
                "Company Location": p.get("Company Location"),
                "Rate": p.get("Rate"),
                "Stage": p.get("Stage"),
                "Date": p.get("Date"),
            }
        )
    print(json.dumps({"ok": True, "count": len(lines), "rows": lines}, indent=2))


def cmd_db_create_opp(args: argparse.Namespace) -> None:
    """Create a Freelance Opportunities row + body from Role Name template."""
    db_id = normalize_id(args.database or freelance_db_id())
    template_id = normalize_id(args.template or role_template_id())
    role = args.role or ""
    company = args.company or ""
    if not role or not company:
        die("--role and --company required", 3)

    # dedupe
    for r in query_rows(db_id):
        p = r["props"]
        if norm(p.get("Role Name")) == norm(role) and norm(p.get("Company")) == norm(
            company
        ):
            print(
                json.dumps(
                    {
                        "ok": True,
                        "duplicate": True,
                        "id": r["id"],
                        "url": r.get("url"),
                    },
                    indent=2,
                )
            )
            return

    location = args.location or ""
    rate = args.rate
    date = args.date or dt.date.today().isoformat()
    stage = args.stage
    if not stage:
        opts = [n for n, _ in select_options(db_id, "Stage")]
        stage = (
            "New"
            if any(x.lower() == "new" for x in opts)
            else (opts[0] if opts else "New")
        )
    link = args.link or ""
    summary = args.summary or ""
    why = args.why or ""

    props: dict[str, Any] = {}
    for name, val in (
        ("Role Name", role),
        ("Company", company),
        ("Company Location", location),
        ("Rate", rate),
        ("Date", date),
        ("Stage", stage),
    ):
        pw = prop_write(db_id, name, val)
        if pw is not None:
            props[name] = pw

    subs = {
        "{Company Name}": company,
        "{Company Location}": location,
        "{Role Name}": role,
        "{Role Description}": summary,
        "{Rate}": "" if rate is None else str(rate),
        "{Reason why you should apply}": why,
        "{Link to the opportunity}": link,
    }
    children = build_template_blocks(template_id, subs)
    payload = {
        "parent": {"database_id": db_id},
        "properties": props,
        "children": children,
    }
    data = request("POST", "/pages", payload)
    print(
        json.dumps(
            {
                "ok": True,
                "duplicate": False,
                "id": data.get("id"),
                "url": data.get("url"),
                "title": role,
                "company": company,
            },
            indent=2,
        )
    )


def cmd_archive(args: argparse.Namespace) -> None:
    oid = normalize_id(args.id)
    data = request("PATCH", f"/pages/{oid}", {"archived": True})
    print(json.dumps({"ok": True, "id": data.get("id"), "archived": True}, indent=2))


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

    s = sub.add_parser("db-schema", help="Dump database property schema")
    s.add_argument(
        "--database",
        default="",
        help=f"DB id (default NOTION_FREELANCE_DB_ID / {DEFAULT_FREELANCE_DB})",
    )
    s.set_defaults(func=cmd_db_schema)

    s = sub.add_parser("db-query", help="List database rows")
    s.add_argument("--database", default="")
    s.add_argument("--limit", type=int, default=100)
    s.add_argument("--raw", action="store_true")
    s.set_defaults(func=cmd_db_query)

    s = sub.add_parser(
        "db-create-opp",
        help="Create Freelance Opportunities row from Role Name template",
    )
    s.add_argument("--database", default="")
    s.add_argument("--template", default="", help="Template page id")
    s.add_argument("--role", required=True)
    s.add_argument("--company", required=True)
    s.add_argument("--location", default="")
    s.add_argument("--rate", type=float, default=None)
    s.add_argument("--date", default="")
    s.add_argument("--stage", default="")
    s.add_argument("--link", default="")
    s.add_argument("--summary", default="")
    s.add_argument("--why", default="")
    s.set_defaults(func=cmd_db_create_opp)

    s = sub.add_parser("archive", help="Archive a page")
    s.add_argument("id")
    s.set_defaults(func=cmd_archive)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
