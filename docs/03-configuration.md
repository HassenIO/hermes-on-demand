# Configuration

Hermes splits settings the official way:

| Kind | File on VPS | Managed from this repo |
|------|-------------|-------------------------|
| Secrets | `~/.hermes/.env` | `.env` on Mac → filtered push |
| Non-secrets | `~/.hermes/config.yaml` | `config/config.yaml.example` |

References:

- [Configuration](https://hermes-agent.nousresearch.com/docs/user-guide/configuration)
- [Environment variables](https://hermes-agent.nousresearch.com/docs/reference/environment-variables)
- [AI providers](https://hermes-agent.nousresearch.com/docs/integrations/providers)

## Cron jobs and model changes

When you change `model.default` / `model.provider` in `config/config.yaml.example` and run **`make push-config`** (or full deploy / update), the remote script `scripts/remote/pin-cron-models.sh` pins Hermes cron jobs to that provider+model via:

```bash
hermes cron edit <job_id> --provider <provider> --model <model>
```

This avoids Hermes `drift_skip` (unpinned jobs refuse to run after global model drift). Jobs that already have an **explicit model different from** `model.default` (e.g. Go newsletter on a strong write model) are **left alone**. To force every job onto the config default:

```bash
PIN_CRON_FORCE=1 bash scripts/remote/pin-cron-models.sh   # on VPS
```

The pin runs after config write on:

- `make push-config` / `./scripts/deploy.sh --config-only`
- full bootstrap
- `make update` / hermes-update
- `make setup-notion` (after config rewrite)

After `make push-config`, re-run **`make cron-push`** if you changed `cron/jobs.json` locally and need overrides re-applied (pin no longer wipes them, but push-config does not upload jobs.json).

## Deploy vs runtime env

### Local-only (Mac `.env`, never written into `~/.hermes/.env`)

| Variable | Required | Description |
|----------|----------|-------------|
| `TARGET_HOST` | yes | VPS hostname or IP |
| `TARGET_USER` | yes | SSH user; owns `~/.hermes` |
| `SSH_PORT` | no | Default `22` |
| `SSH_IDENTITY_FILE` | no | Extra `-i` key path |
| `REMOTE_DIR` | no | Payload dir on VPS (default `~/hermes-setup`) |
| `TIMEZONE` | no | IANA TZ for VPS (`timedatectl`); default `Asia/Dubai`. Applied on every deploy; also written to VPS `~/.hermes/.env` as `TIMEZONE` + `TZ` |

### Hermes runtime (pushed to VPS `~/.hermes/.env`)

| Variable | Required | Description |
|----------|----------|-------------|
| `OPENROUTER_API_KEY` | yes | [OpenRouter](https://openrouter.ai/keys) |
| `TELEGRAM_BOT_TOKEN` | yes | From @BotFather |
| `TELEGRAM_ALLOWED_USERS` | yes | Numeric Telegram user ids |
| `TELEGRAM_HOME_CHANNEL` | no | Home chat for cron; or use `/sethome` |
| `TELEGRAM_HOME_CHANNEL_NAME` | no | Display label |
| `TELEGRAM_GROUP_ALLOWED_USERS` | no | Group sender allowlist |
| `TELEGRAM_GROUP_ALLOWED_CHATS` | no | Group chat id allowlist |
| `DISCORD_BOT_TOKEN` | no* | Discord bot token (*both Discord vars required to enable — see [07-discord-gateway](07-discord-gateway.md)*) |
| `DISCORD_ALLOWED_USERS` | no* | Numeric Discord user ids allowlist |
| `DISCORD_HOME_CHANNEL` | no | Discord channel id for cron / proactive home |
| `DISCORD_HOME_CHANNEL_NAME` | no | Display label |
| `DISCORD_FREE_RESPONSE_CHANNELS` | no | Channel ids that skip @mention |
| `DISCORD_ALLOWED_CHANNELS` | no | If set, only these channels (+ DMs) |
| `DISCORD_IGNORED_CHANNELS` | no | Never respond here |
| `DISCORD_REQUIRE_MENTION` | no | Default true in server channels |
| `DISCORD_AUTO_THREAD` | no | Default true |
| `DISCORD_ALLOW_BOTS` | no | Default `none` |
| `GATEWAY_ALLOW_ALL_USERS` | no | Keep `false` / unset on VPS |
| `FIRECRAWL_API_KEY` | no | Web scraping if enabled |
| `NOTION_API_KEY` | no* | Notion internal integration (`ntn_…`). *Both Notion vars required together* |
| `NOTION_REPORTS_PARENT_PAGE_ID` | no* | Parent page UUID. Without this, Notion is **not** configured even if the key is set |
| `NOTION_TOKEN` | no | Alias of `NOTION_API_KEY` for MCP (set automatically when both are present) |
| `VOICE_TOOLS_OPENAI_KEY` | no | Cloud STT/TTS |
| `GROQ_API_KEY` | no | Groq Whisper STT |
| `GITHUB_TOKEN` | no | Skills hub rate limits |

Full upstream list: [Environment variables](https://hermes-agent.nousresearch.com/docs/reference/environment-variables).

## Model (config.yaml)

Pinned in `config/config.yaml.example`:

```yaml
model:
  provider: openrouter
  default: xiaomi/mimo-v2.5
```

- Provider uses `OPENROUTER_API_KEY` from `.env`
- Model catalog page: [xiaomi/mimo-v2.5](https://openrouter.ai/xiaomi/mimo-v2.5)
- Change model later on the VPS with `hermes model`, or edit `config.yaml` and `./scripts/deploy.sh --config-only`

Do **not** put `LLM_MODEL` in `.env` — upstream removed that; `config.yaml` is source of truth.

## Terminal / Docker backend

```yaml
terminal:
  backend: docker
  docker_image: "nikolaik/python-nodejs:python3.11-nodejs20"
  container_cpu: 1
  container_memory: 2048
```

- Agent shell commands run inside Docker, not as unrestricted host root
- Host `~/.hermes/.env` secrets are **not** forwarded into the container unless listed under `docker_forward_env`
- If the agent generates files for Telegram `MEDIA:`, mount a host-visible path (see [Telegram docs — Docker MEDIA](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/telegram))

## Applying config changes

```bash
# From Mac, after editing .env or config/config.yaml.example:
./scripts/deploy.sh --config-only
```

Or on the VPS:

```bash
hermes config set model.default xiaomi/mimo-v2.5
hermes config set terminal.backend docker
hermes gateway restart
```

## Inspect on VPS

```bash
hermes config
hermes doctor
hermes gateway status
```
