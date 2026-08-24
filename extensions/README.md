# Extensions

Optional capabilities deployed to the VPS alongside Hermes.

| Name | Type | Deploy | Doc |
|------|------|--------|-----|
| Firecrawl | service | `./scripts/deploy.sh --firecrawl` | [docs/tools/firecrawl.md](../docs/tools/firecrawl.md) |
| Mnemosyne | hermes-plugin | `./scripts/deploy.sh --mnemosyne` | [docs/tools/mnemosyne.md](../docs/tools/mnemosyne.md) |
| Agent-Reach | skill+cli | `./scripts/deploy.sh --agent-reach` | [docs/tools/agent-reach.md](../docs/tools/agent-reach.md) |

See [registry.yaml](registry.yaml) for defaults and skip flags.

## Adding an extension

1. Add `extensions/<name>/` (Dockerfile, skill, assets as needed).
2. Add `scripts/remote/<name>-up.sh` (idempotent, runs on VPS).
3. Wire `./scripts/deploy.sh --<name>` + optional full-deploy default + `SKIP_*`.
4. Hook healthcheck / hermes-update if needed.
5. Document under `docs/tools/<name>.md`.
