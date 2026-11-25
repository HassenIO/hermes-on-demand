# Agent-Reach

Give Hermes eyes on the open internet via [Agent-Reach](https://github.com/Panniantong/Agent-Reach): platform CLIs inside the **Docker terminal** sandbox, plus a Hermes skill.

## What you get (v1 — zero-config)

| Channel | Tool |
|---------|------|
| Web → Markdown | `curl` + [Jina Reader](https://r.jina.ai) |
| YouTube | `yt-dlp` |
| GitHub (public) | `gh` |
| RSS/Atom | `feedparser` |
| Semantic search | `mcporter` + Exa (if available) |
| Bilibili | `bili` / bili-cli |

The image is built on `nousresearch/hermes-sandbox:desktop`, so it also carries the Bot Desktop stack (Xvnc, xfce, Playwright Chromium). Hermes `browser_*` tools start inside the sandbox. Without it they fail with `Bot Desktop needs Xvnc ... inside the terminal backend's sandbox`.

The Dockerfile also installs the `agent-browser` CLI, which Hermes runs by name in the sandbox. Desktop images after v0.21 dropped it. Without it the browser fails with `exec: agent-browser: not found`. Keep `AGENT_BROWSER_VERSION` in step with `agent-browser` in `~/.hermes/hermes-agent/pm/lock.json` on the VPS after `make update`. Do not fix that with `bot_desktop.placement: gateway`: that runs the browser next to `~/.hermes/.env`.

**Not in v1:** Twitter/Reddit cookies, OpenCLI desktop sessions, XiaoHongShu MCP.

Generic scrape/search still uses **Firecrawl** (`web.backend: firecrawl`). Use Agent-Reach for platform-specific flows.

## Deploy

```bash
# From the local control plane
./scripts/deploy.sh --agent-reach

# Or full bootstrap (default includes Agent-Reach)
./scripts/deploy.sh

# Opt out on full deploy
SKIP_AGENT_REACH=1 ./scripts/deploy.sh
```

Pin a git ref (optional):

```bash
AGENT_REACH_REF=main ./scripts/deploy.sh --agent-reach
```

## What the installer does (VPS)

1. Builds Docker image `hermes-terminal:agent-reach` from `extensions/agent-reach/docker/Dockerfile`, pulling the latest `desktop` base, and checks the CLIs and desktop binaries
2. Installs skill → `~/.hermes/skills/agent-reach/SKILL.md`
3. Sets `terminal.docker_image` and mounts `~/.agent-reach`
4. Removes old Hermes sandbox containers so the new image is used
5. Optional host CLI at `~/.hermes/.agent-reach/venv` for `agent-reach doctor`
6. Restarts gateway

## Verify

```bash
./scripts/deploy.sh --health

# On VPS
docker image inspect hermes-terminal:agent-reach
docker run --rm hermes-terminal:agent-reach yt-dlp --version
ls ~/.hermes/skills/agent-reach/SKILL.md
hermes config get terminal.docker_image
```

In Telegram: **`/new`**, then e.g. “Summarize this YouTube video: …” or “What is github.com/…?”.

## Layout

```
extensions/agent-reach/
  docker/Dockerfile
  skill/SKILL.md
scripts/remote/agent-reach-up.sh
```

## Updates

`./scripts/deploy.sh --update` refreshes the image + skill when Agent-Reach was previously installed.

## Security

- Tools run **inside** the Docker terminal sandbox (not host shell).
- No social cookies in v1.
- Optional `GITHUB_TOKEN` via `terminal.docker_forward_env` (from `~/.hermes/.env`).
