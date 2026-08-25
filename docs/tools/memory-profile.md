# User profile & memory (as code)

Hermes **does** use `USER.md` — the model sometimes claims otherwise because it only “sees” the **memory tool**, not the filename. Official docs:

- [Persistent Memory](https://hermes-agent.nousresearch.com/docs/user-guide/features/memory)
- [Personality & SOUL.md](https://hermes-agent.nousresearch.com/docs/user-guide/features/personality)

## Files (VPS)

| Store | Path | Purpose |
|-------|------|---------|
| Soul / persona | `~/.hermes/SOUL.md` | Agent identity (system prompt slot #1) |
| User profile | `~/.hermes/memories/USER.md` | Who you are (`memory` tool `target=user`) |
| Agent notes | `~/.hermes/memories/MEMORY.md` | Environment / lessons (`target=memory`) |

## Repo seeds (`artifacts/`)

| Local | Installed to |
|-------|----------------|
| `artifacts/SOUL.md` | `~/.hermes/SOUL.md` |
| `artifacts/USER.md` | `~/.hermes/memories/USER.md` |
| `artifacts/MEMORY.md` | `~/.hermes/memories/MEMORY.md` |
| `artifacts/CV.md` | `~/.hermes/CV.md` (on-demand; not injected every turn) |

`CV.md` is a full professional profile for freelancing/role-fit. `USER.md` only holds a **pointer** to `~/.hermes/CV.md` so the agent `read_file`s it when needed (avoids burning tokens every message). The Docker sandbox mounts `CV.md` read-only.

Deploy:

```bash
./scripts/deploy.sh --artifacts    # profile files only + gateway restart
./scripts/deploy.sh --config-only  # config + secrets + artifacts
./scripts/deploy.sh                # full bootstrap (includes artifacts)
```

Then in Telegram: **`/new`** so the frozen memory snapshot reloads.

## File format (critical)

`USER.md` and `MEMORY.md` are **not** free-form docs. They are lists of entries joined by:

```text
\n§\n
```

Example `USER.md`:

```text
Name: Hassen. Lives in Dubai, UAE. Timezone: Asia/Dubai.
§
Prefers concise, actionable answers.
§
Works as an AI engineer; interested in Go (Baduk).
```

Limits (defaults): user **1,375** chars, memory **2,200** chars total.

Hermes injects these at **session start** as:

- `USER PROFILE (who the user is)`
- `MEMORY (your personal notes)`

Mid-session `memory` tool writes update disk immediately but only appear in the system prompt on the **next** session (`/new` or new chat).

## Config

```yaml
# config/config.yaml.example → ~/.hermes/config.yaml
memory:
  memory_enabled: true
  user_profile_enabled: true
  memory_char_limit: 2200
  user_char_limit: 1375
```

## Why the bot said “no USER.md” / tried Docker `read_file`

1. **Profile is already in the system prompt** — it should answer from memory, not open files.
2. **If it still tries `read_file`**, Docker must work. On Telegram, session IDs contain `:` which used to break Docker volume mounts (`too many colons`, exit 125). Fixed by `scripts/remote/patch-hermes-docker.sh` (applied on bootstrap).
3. **Sandbox mount** — `config.yaml` mounts `~/.hermes/memories` read-only into the container so disk reads of `USER.md` work if needed.
4. After deploy: **`/new`** so the frozen snapshot reloads.

After seeding with `./scripts/deploy.sh --artifacts` and `/new`, ask: *“What do you know about me?”* — it should reflect the seeded entries without reading files.
