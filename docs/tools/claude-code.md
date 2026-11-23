# Claude Code

Hermes can hand coding work (clone, edit, review, refactor) to the Claude Code CLI through its bundled `claude-code` skill. The skill runs `claude -p "<task>"` with the terminal tool. With the Docker backend that means `claude` runs **inside the agent sandbox**, not on the VPS host.

Upstream skill: [autonomous-ai-agents/claude-code](https://hermes-agent.nousresearch.com/docs/user-guide/skills/bundled/autonomous-ai-agents/autonomous-ai-agents-claude-code).

## Pieces

| Piece | Where |
|-------|-------|
| CLI (pinned `CLAUDE_CODE_VERSION`, auto-updater off) | `extensions/agent-reach/docker/Dockerfile` → image `hermes-terminal:agent-reach` |
| Auth token | `CLAUDE_CODE_OAUTH_TOKEN` in local `.env` → `build_runtime_env` → VPS `~/.hermes/.env` |
| Sandbox access | `terminal.docker_forward_env` in `config/config.yaml.example` |
| Skill | Bundled with Hermes. Not in this tree |

## Setup

1. On any machine with Claude Code, run `claude setup-token` and log in with your Claude subscription. Put the token in `.env` as `CLAUDE_CODE_OAUTH_TOKEN=`. Do not use `ANTHROPIC_API_KEY`; that bills per token.
2. Rebuild the sandbox image: `make setup-agent-reach`.
3. Push the env and config: `make push-config`, then `/new` in Telegram.
4. Check the skill is installed (on the VPS, inside the gateway): `hermes skills list | grep claude-code`. If missing: `hermes skills install official/autonomous-ai-agents/claude-code`. Never bare `hermes update`; use `make update`.

## Verify

Ask the bot: "Use claude-code to run `claude auth status --text` and tell me the result." Expect a logged-in subscription. Then try a small task, for example summarizing a public repo's README.

## Limits

- **Root sandbox.** The container runs as root, and the skill only uses `--dangerously-skip-permissions` for non-root users. Expect `--permission-mode acceptEdits`, `--allowedTools`, `--max-turns`, and `--max-budget-usd` instead.
- **Resources.** `container_memory: 768` and `timeout: 180` are tight for long runs. Raise them in `config/config.yaml.example` if the VPS has headroom, or keep tasks small.
- **Usage.** Runs count against the same Claude subscription limits as the Hermes chat model.
- **Exposure.** Anything in the sandbox can read the token. Rotate it with `claude setup-token` if it leaks, then `make push-config`.
- **GitHub.** `GITHUB_TOKEN`, if set, is already forwarded, so `gh` and `git push` work from the sandbox.
