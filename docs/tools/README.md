# Tools

Documentation for optional services and Hermes tool integrations deployed with this repo.

Each tool gets its own page under `docs/tools/`. Code and compose files live next to the tool (e.g. `firecrawl/`).

| Tool | Doc | Deploy |
|------|-----|--------|
| Firecrawl (web scrape / search) | [firecrawl.md](firecrawl.md) | `./scripts/deploy.sh --firecrawl` |
| Memory / USER profile | [memory-profile.md](memory-profile.md) | `./scripts/deploy.sh --artifacts` |

## Adding a future tool

1. Put runtime assets under a top-level folder (e.g. `mytool/`).
2. Add a remote script if needed: `scripts/remote/mytool-up.sh`.
3. Wire a flag in `scripts/deploy.sh` (e.g. `--mytool`).
4. Document it here as `docs/tools/mytool.md` and link it in this table.
5. Extend `.env.sample` / `config/config.yaml.example` with the required keys.
