# Factory

The `factory` skill turns GitHub issues into pull requests.
Hermes is the orchestrator: it triages issues, starts one Claude Code agent per issue, verifies the result, and opens the PR.
Agents implement and commit locally.
You review and merge.
Hermes never merges, approves, force-pushes, or pushes to the base branch.

The skill is custom and gitignored like every other skill: [skills/software-development/factory/SKILL.md](../../skills/software-development/factory/SKILL.md).
It drives the Claude Code CLI described in [claude-code.md](claude-code.md).

## Commands (in Telegram)

| You say | Hermes does |
|---------|-------------|
| `factory init <owner/repo>` plus any context | Clones the repo, creates the `factory:*` labels, tunes `config.json` from CI and package scripts, writes `context.md`, and asks you to confirm |
| `factory run [owner/repo]` | One pass: sweep issues labeled `factory`, triage or split them, start or resume agents, verify, open PRs, ask you when an agent is stuck |

Only issues you label `factory` are touched.
State lives in GitHub labels, so you steer by relabeling.

## How it runs on the VPS

| Piece | Where |
|-------|-------|
| Skill scripts | `~/.hermes/skills/software-development/factory/`, mounted read-only in the sandbox |
| Agents (`claude -p`) | Docker terminal sandbox (`hermes-terminal:agent-reach`), started as background terminal jobs |
| Clones, worktrees, logs, locks | VPS `~/.hermes/factory/<owner>__<repo>/`, mounted at the same path in every sandbox |
| Claude Code config and sessions (`--resume`) | VPS `~/.hermes/claude-code/`, mounted at `/root/.claude` in every sandbox, with `CLAUDE_CONFIG_DIR=/root/.claude` |
| GitHub access | `GITHUB_TOKEN`, forwarded to the sandbox; `factory-init.sh` sets the `gh` credential helper and git identity in each clone |
| Claude access | `CLAUDE_CODE_OAUTH_TOKEN`, forwarded to the sandbox; usage counts against the Claude subscription |

The sandbox `/root` is keyed per surface, so a chat pass and a cron pass may not share it.
The two mounts above make state and agent sessions shared anyway.
The run lock is a heartbeat file, not a PID, for the same reason.

Agents run with `--permission-mode acceptEdits`, a per-repo `allowed_bash` list, and a deny list (`git push`, `gh`, `curl`, destructive git).
They cannot push or call GitHub; Hermes does that after it re-runs the repo's checks itself.

## Setup

1. `GITHUB_TOKEN` in `.env` needs `repo` scope (and `project` if you want PRs moved on a Projects board).
2. `CLAUDE_CODE_OAUTH_TOKEN` in `.env`, see [claude-code.md](claude-code.md#setup).
3. Put the skill in `skills/software-development/factory/` locally, then `make skills-push`.
4. `make push-config` (sandbox memory and the two mounts), then `/new` in Telegram.

## Try it on a project

1. In Telegram: `factory init owner/repo` and add any context agents should know (architecture, no-go areas).
2. Check the config Hermes proposes, mainly `allowed_bash` and `verify_commands`, and confirm.
3. On GitHub, open a small issue with clear acceptance criteria and label it `factory`.
   Add `factory:ready` too to skip triage.
4. In Telegram: `factory run owner/repo`.
   Hermes posts a status table and ends the turn; it reports back when the agent finishes.
5. Review the PR on GitHub.
   To request changes, review normally and run `factory run` again; the agent resumes with your comments.

Inspect a run on the VPS: `ls ~/.hermes/factory/<owner>__<repo>/logs/`.
A lock file `issue-N.running` modified in the last 3 minutes means an agent is working on issue N.

## Limits

- **One agent at a time.** The VPS has 1 vCPU and 1.6 GB RAM with swap; `container_memory: 1280` fits one agent with its install, build, and tests. Keep `max_parallel: 1`. Raise both only on a bigger host.
- **Gateway restarts stop running agents.** `make push-config` and `make update` restart the gateway. The next `factory run` sees the stale lock and resumes or restarts the issue.
- **No browser checks for UI diffs** beyond what the sandbox Chromium can show; Hermes says what it could not see.
- **Exposure.** Anything in the sandbox can read both tokens. Use a fine-grained GitHub token limited to the repos you hand to the factory.
