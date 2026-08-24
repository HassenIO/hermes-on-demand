# Mnemosyne (Hermes memory provider)

[Mnemosyne](https://github.com/mnemosyne-oss/mnemosyne) is a local-first SQLite memory layer for Hermes.

Canonical upstream docs:

- [Hermes integration](https://github.com/mnemosyne-oss/mnemosyne/blob/main/docs/hermes-integration.md)
- [LLM install guide — Path A (side venv + wrapper)](https://github.com/mnemosyne-oss/mnemosyne/blob/main/docs/llm-installation-guide.md)

## Why side-venv + wrapper

Installing into Hermes’ own venv is wiped by `hermes update`. Official guidance for durable installs:

1. Create a **side venv** with the **same Python** as the Hermes gateway  
2. `pip install mnemosyne-memory[embeddings] mnemosyne-hermes` there  
3. `mnemosyne-hermes install --mode wrapper --python <side-venv-python>`  
4. `hermes config set memory.provider mnemosyne`

Data stays under `$HERMES_HOME` (default `~/.hermes/mnemosyne/data`).

## Deploy (this repo)

```bash
# Standalone
./scripts/deploy.sh --mnemosyne

# Included in full deploy by default (opt out: SKIP_MNEMOSYNE=1)
./scripts/deploy.sh
```

Optional:

```bash
MNEMOSYNE_PROFILE=all ./scripts/deploy.sh --mnemosyne   # heavier local LLM extras
```

On small VPS (~1.5–2 GB), default `embeddings` is used. When `OPENROUTER_API_KEY` is present, the installer also sets remote embedding env vars so vectors can go through OpenRouter instead of only local models.

## After install

```bash
# On VPS
hermes memory status          # Provider: mnemosyne
~/.hermes/.mnemosyne/venv/bin/mnemosyne stats
hermes tools list | grep mnemosyne_
```

In Telegram: **`/new`**, then use the agent normally (Mnemosyne captures turns and exposes `mnemosyne_*` tools).

## Survive Hermes updates

```bash
./scripts/deploy.sh --update
```

That upgrades Hermes **and** the Mnemosyne side-venv, then refreshes the wrapper.

Manual on VPS:

```bash
bash ~/hermes-setup/scripts/remote/hermes-update.sh
# or only Mnemosyne:
bash ~/hermes-setup/scripts/remote/mnemosyne-up.sh
```

## Do not

- `hermes tools disable memory` — that can hide provider tools too  
- Install only into Hermes’ venv without a wrapper (lost on update)  
- Symlink profiles straight to `site-packages/mnemosyne_hermes` (bypasses wrapper bootstrap)

## Relation to artifacts/USER.md

Built-in `USER.md` / `MEMORY.md` seeds still deploy via `--artifacts`. Mnemosyne is an **external** provider alongside them. On install we also **seed** USER.md `§` entries into Mnemosyne via `mnemosyne store`.
