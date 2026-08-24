# Tools

Documentation for optional services and Hermes tool integrations deployed with this repo.

Each tool gets its own page under `docs/tools/`. Code and compose files live next to the tool (e.g. `firecrawl/`).

| Tool | Doc | Deploy |
|------|-----|--------|
| Firecrawl (web scrape / search) | [firecrawl.md](firecrawl.md) | `./scripts/deploy.sh --firecrawl` |
| Memory / USER profile (built-in) | [memory-profile.md](memory-profile.md) | `./scripts/deploy.sh --artifacts` |
| Mnemosyne (external memory) | [mnemosyne.md](mnemosyne.md) | `./scripts/deploy.sh --mnemosyne` |
| Agent-Reach (platform web CLIs) | [agent-reach.md](agent-reach.md) | `./scripts/deploy.sh --agent-reach` |

Extension registry: [extensions/registry.yaml](../../extensions/registry.yaml).

## Adding a future tool

1. Prefer `extensions/<name>/` + `scripts/remote/<name>-up.sh` (see [extensions/README.md](../../extensions/README.md)).
2. Wire a flag in `scripts/deploy.sh` and optional `SKIP_*` on full deploy.
3. Hook `healthcheck.sh` / `hermes-update.sh` if needed.
4. Document here as `docs/tools/<name>.md` and register in `extensions/registry.yaml`.
5. Extend `.env.sample` / `config/config.yaml.example` with required keys.
