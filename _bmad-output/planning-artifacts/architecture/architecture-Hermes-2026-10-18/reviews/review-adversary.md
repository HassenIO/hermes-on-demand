# Adversary review — Hermes control plane spine

Verdict: **fix**

Altitude is feature, so the units below are epics, or stories that must ship together inside one epic. Each pair obeys every AD Rule as written. Deferred interim rules were not treated as holes. Style was ignored. A pair is a hole only when both sides can cite Rule text and still ship artifacts that do not fit.

Brownfield scripts already pick one side of several pairs. That does not close the hole. The next epic is told to obey the spine, not to copy an unstated script habit.

## F1 — critical — The sandbox ref is not bound to the tree `make deploy` syncs, and "pr-checks.yml success" is not a query

Close by tightening AD-5 (and one sentence in AD-6).

### Pair A — two checkouts, one mutator

**Story Checkout** cites AD-5: "resolves that pull request's head SHA, requires a same-repo pull request, requires `pr-checks.yml` success for that SHA, then checks out that SHA." It checks the SHA out to `pr-src/` so the master workflow file that GitHub is executing stays untouched. AD-5 also says both clicks are "workflow_dispatch of the workflow file on master." Keeping that file's tree at the workspace root satisfies that sentence.

**Story Deploy** cites AD-6: "Both clicks run `make deploy` and nothing else." It runs that in `$GITHUB_WORKSPACE`. AD-1 names `scripts/deploy.sh` as the mutator. `ROOT` is the parent of that script. Nothing in either Rule says the checkout path is that `ROOT`.

Result: the SHA is checked out, and `make deploy` syncs master. Sandbox "deployed the pull request" under a literal reading. Prod is safe only because AD-5 says it checks out `master` only — the same gap exists if prod ever has two trees.

The paradigm ("desired state is one git ref plus one environment's secret set") does not close it. It does not say which directory is that ref when two checkouts exist.

**Tighten:** Capture one SHA. Require success for that exact SHA (see pair B). Check that SHA out as the workspace `make deploy` runs in. `make deploy` executes that tree's `scripts/deploy.sh` and syncs that tree. Prod: the checkout of `master` is that tree. Do not checkout the candidate to a side path.

### Pair B — two success tokens

**Story Latest-run** cites AD-5 "requires `pr-checks.yml` success for that SHA." It asks the Actions API for workflow runs of `.github/workflows/pr-checks.yml` whose `head_sha` is that SHA, and requires the latest run's `conclusion` to be `success`. A missing run, a failure, a cancellation, or an in-progress run is not success. An older green run does not count.

**Story Any-check** cites the same sentence. It looks for a check-run named `PR checks` (the workflow `name`) or job id `check`, and accepts any successful run for that SHA. A later failed or in-progress run does not revoke the older green.

AD-15 says the checks "are `bash -n` … and `uv run --no-env-file pytest`." It does not name the GitHub check, the job id, or latest-versus-any. Both stories obey AD-15. They disagree on the bit AD-5 uses as the gate. One click deploys a SHA the other must refuse.

**Tighten:** Success means the latest workflow run of `.github/workflows/pr-checks.yml` for that exact head SHA has `conclusion=success`. Name the permission that query needs (`actions: read`). Do not accept a check-run name, a commit status, or an older run. The comment line in `pr-comment.mjs` is a human signal, not this predicate. A missing comment is not a failed check and is not a pass.

## F2 — high — `~/.hermes/config.yaml` has many writers, no patch rule, and no order

Close with a new AD, or tighten AD-13.

**Epic Extract** cites AD-13 (the up script is the extension mutator) and AD-11 (after a full deploy, extract is loopback Firecrawl, default mode lite). It also cites AD-2: "One `config/config.yaml.example` serves both hosts." Its up script installs that example onto `~/.hermes/config.yaml`, then sets the web keys. That is how it stops a second behavior file.

**Epic Memory** cites AD-13 and AD-18: "`memory.provider` is `mnemosyne` after setup." It installs the same example, then sets `memory.provider`. **Epic Agent-Reach** cites AD-11: "On a full deploy the default sandbox image is the Agent-Reach image unless that extension is skipped." It installs the example, then sets `terminal.docker_image`.

AD-13 says they "run" on a full deploy. The sentence is a list joined by "and", not an order. Extract reads it as the sequence written (search/extract, then Mnemosyne, then Agent-Reach). Agent-Reach reads it as a set and runs first, because AD-11 makes the image the default for the deploy, including if a later step fails.

AD-14 does not stop the clash. "Config push must not drop those mounts" names config push, not a full-deploy up script. A click is `make deploy` (AD-6), not config push. Each up script can replace the file and still obey AD-14.

Last writer wins. The other's keys are gone. AD-19 does not go red: a missing default-stack piece is a warning, not an exit failure. Health stays green.

The same hole is the image identity. AD-11 and AD-19 say "the Agent-Reach image" and never name the tag. Setup tags `hermes-terminal:agent-reach`. Health looks for `agent-reach:latest`. One says the image is present. The other says it is missing. `yt-dlp` is then required or not, so AD-19's exit bit flips.

**Tighten:** Extension up scripts patch only their own keys. They do not install or replace `config.yaml`. Full-deploy order is bootstrap (the one install of `config.yaml.example`), then search/extract, then Mnemosyne, then Agent-Reach, then Notion, then snapshot. Name the Agent-Reach image tag in both AD-11 and AD-19. One string.

## F3 — high — Two mutation paths for one gateway process

Close by tightening AD-10.

**Story Config-push** cites AD-10: "Config push and control-plane upgrade restart the gateway." After it rewrites env and config, it restarts. A new token is what the process holds.

**Story Click** cites AD-6: "Both clicks run `make deploy` and nothing else." It cites AD-10's restart list and does not add a restart: full deploy and bootstrap are not on it. AD-19 fails health only if the gateway process is missing, not if it is stale. A process left over from the previous click satisfies health. Conventions say re-running bootstrap "still rewrites env and config." The click writes the new secret set and leaves the old process.

Both ship. They are the two supported ways to change secrets (AD-10 names config push; AD-6 names the click). After a token rotation, config push reloads the process and the click does not. AD-1's "successful full deploy ends in the health check" does not force a reload.

A second pair, same entity. **Epic Extract** cites the AD-10 list and the AD-13 registration list (directory, up script, case, Make target, registry entry, doc, placeholders). Restart is on neither list, so `firecrawl-up.sh` does not restart. **Epic Memory** cites AD-18 "after setup" as the running process, and restarts inside `mnemosyne-up.sh`. If Extract runs after that restart, its keys are on disk and not in the process. Health still passes (AD-19: missing Firecrawl is a warning).

**Tighten:** Full deploy restarts `hermes-gateway` once, after extension up scripts and after the env and config writes, before the health check. Extension up scripts do not restart it. Config push and control-plane upgrade still restart, as now. "After setup" means the process has loaded the new provider, which the single end restart satisfies.

## F4 — high — Ambient `GITHUB_TOKEN` may or may not enter the runtime env

Close by tightening AD-3 and AD-11.

**Epic Sandbox-click** cites AD-11: "`GITHUB_TOKEN` may be forwarded into the sandbox when set." It cites AD-8: the never-forward list does not include `GITHUB_TOKEN`, and `build_runtime_env` is the only runtime-env writer. GitHub sets `GITHUB_TOKEN` on the job. The epic writes `$ROOT/.env` from the GitHub Environment (AD-3) and does not unset the ambient token. `load_dotenv` does not clear it. The filter copies it. The sandbox receives the runner token.

**Epic Prod-click** cites AD-3: the runner writes `.env` "from exactly one GitHub Environment." The runner token is not a secret of that environment. The epic unsets `GITHUB_TOKEN` before `make deploy`. AD-11 says "may", not "must", so omission is compliant. AD-8 is satisfied because the filter still forwards the name when it is set.

Same rules, two runtime envs. Sandbox and prod are not required to match each other, but each click is built from the same sentences and can pick either shape. The token's `permissions` block is also unpinned, so one story's token can push and the other's cannot.

**Tighten:** Before `make deploy`, unset `GITHUB_TOKEN` unless that name is a secret in the one GitHub Environment in use. Do not forward the ambient runner token. Sandbox workflow permissions are the minimum that can resolve a same-repo pull request and read workflow runs (`contents: read`, `pull-requests: read`, `actions: read`). Prod is `contents: read`. Say so in AD-5.

## F5 — high — Prod preflight is not the deploy SSH contract

Close by tightening AD-6.

**Story Account** cites AD-6 (refuse unless one of the two paths exists on the target) and AD-16 (`BatchMode=yes`, `StrictHostKeyChecking=accept-new`). It cites AD-3 (secret names match variable names) and reads `TARGET_USER`, `TARGET_HOST`, `SSH_PORT`, and `SSH_IDENTITY_FILE` from the materialized `.env`. It SSHes as that user. Remote `~` is that user's home. It uses `test -e`, because the Rule says "exists".

**Story Literal** cites the same AD-6 paths and the same AD-16 flags. It does not cite a port, a user, or `-x`. It SSHes as `root` because `/usr/local/lib/...` is a system path, uses port 22, and tests `test -x`. On the target, `~/.hermes/...` is `/root/.hermes/...`.

Both check "on the target." A host whose only binary is `/home/ubuntu/.hermes/hermes-agent/venv/bin/hermes` on port 2222 is refused by Story Literal and accepted by Story Account. AD-6 says the preflight is not inside `deploy.sh`, so it will not accidentally inherit `ssh_cmd`. AD-9 forbids the click from calling `make ssh`, so it also will not inherit that target's user handling.

**Tighten:** Preflight SSHes as `TARGET_USER` from the materialized `.env`, with `SSH_IDENTITY_FILE` and `SSH_PORT` (default 22), and AD-16 options. It does not call `make ssh`. It tests remote `test -e` on the two paths, with `~` expanded by that remote account. Non-zero refuses. Then `make deploy`.

## F6 — medium — Two relink owners, two venv paths

Close by tightening AD-10.

**Story Config-push** cites AD-10: "Config push also relinks the `hermes` command" and "A broken `hermes` command is repaired by relinking to the venv binary." It links `~/.local/bin/hermes` at `/usr/local/lib/hermes-agent/venv/bin/hermes` only. That is "the" venv binary. The second AD-6 path is not named here.

**Story Health** cites the same repair sentence, plus AD-6's two paths. It relinks to whichever exists, and it does the relink inside healthcheck, because that is when a broken command is seen. "Health … does not upload a payload" does not forbid a relink. "Reapplies the patch only when the marker is missing" constrains when the patch runs, not every other health mutation.

Next config push rewrites the symlink onto the `/usr/local/lib` path. If the live binary is only the `~/.hermes/hermes-agent` path, the command breaks. Health then "repairs" it the other way. The two named repair stories undo each other. AD-10's Prevents is a CD path that cannot repair a broken `hermes` command. The Rule text creates two repairs.

**Tighten:** One relink helper. Target is the first of the two AD-6 paths that exists, in the order AD-6 writes them. Config push calls it. Health may call the same helper. Health does not invent a third path (`/usr/local/bin/hermes` is not a venv binary). Full deploy calls it before the end restart in F3.

## F7 — medium — A missing bucket fails the click, or it does not

Close by tightening AD-1 and AD-14.

**Story Health-ends** cites AD-1: "A successful full deploy ends in the health check." Health is the last step. Its exit is the deploy exit (AD-19). Snapshot runs before that, when the four variables are set (AD-13). AD-14 says "A missing bucket fails the snapshot," not the deploy. The story contains that failure (`warn`) so a successful deploy can still end in health. The click is green. The snapshot script has still failed.

**Story Snapshot-fails-deploy** cites AD-13 (snapshot runs on full deploy when the four variables are set), AD-14 (a missing bucket fails the snapshot), and the convention that bash scripts start with `set -euo pipefail`. It does not catch the failure. `make deploy` exits non-zero. That deploy is not a "successful" one, so AD-1's last sentence does not apply. When the bucket exists, health still runs last and the successful deploy ends there.

AD-6 says both clicks run `make deploy` and nothing else, so the click's color is this exit code. One story's prod click is green with a missing bucket. The other's is red. Both end successful deploys in the health check.

**Tighten:** Pick one and write it into AD-1. Recommended, matching AD-19's warning-versus-failure split: snapshot failure does not fail `make deploy`; health is last; health's exit is the deploy exit. Say the opposite if a missing bucket must fail the click. Do not leave both.

## F8 — medium — Operator `FIRECRAWL_MODE` is honored, or it is not

Close by tightening AD-11.

**Story Always-lite** cites AD-11: "Default extract mode is lite and is not written into the runtime env." It cites AD-8: `FIRECRAWL_MODE` is never forwarded. It never passes the variable, including on the up-script command line. The up script's own default is lite. An operator value in `.env` is ignored.

**Story Command-prefix** cites the same two sentences. "Not written into the runtime env" is satisfied by leaving it out of `build_runtime_env`. "Default" applies when the variable is unset. When the operator set it, the story passes `FIRECRAWL_MODE` on the `ssh` command that runs `firecrawl-up.sh`. That is not the runtime env, so AD-8 holds.

Same `.env`, two hosts: lite versus full. Loopback bind still holds either way (AD-11), so both look compliant. Full versus lite is the trade-off AD-11 tried to freeze and did not.

**Tighten:** The up script receives `FIRECRAWL_MODE` only from the operator env, default `lite` when unset or empty. It is never written into the runtime env. Say whether `full` is a legal operator value. If it is not, the up script must refuse it.

## Not holes

Checked and dropped. A Deferred interim rule already freezes the choice, or the second unit cannot cite the Rule and still diverge.

- Open Questions 1, 5, and 6, the actor allowlist, pinned `known_hosts`, voice behavior, and firewall/fail2ban/spend/webhook. Deferred table. Do not implement.
- Skill push, cron push, and seed push on a click. AD-1 and AD-6 forbid them.
- Concurrency group names and `cancel-in-progress: false`. AD-17 pins them. A laptop overlap is a gap both units can omit. It is not a pair that builds two locks.
- A second snapshot key layout. AD-14 "one writer per prefix" forbids a second uploader. No reader is in scope ("does not restore"). A watcher is not licensed by any Rule; adding one does not cite a Rule.
- Allowlist numeric versus "does not evaluate." The second unit evaluates. That violates AD-12.
- Comment line wording. No Rule makes another unit parse it. Format is style. Pair B above already says it is not the gate.
- `ALLOW_LOCAL_TARGET` empty versus omitted. AD-9 refuses anything other than exact `1`. AD-8 never forwards `PIN_CRON_FORCE`.
- Prod preflight stricter than the bootstrap skip. Conventions already say the preflight is not a description of that skip.
- Running the candidate's `deploy.sh` with sandbox secrets. Accepted by AD-5 once the tree in F1 is the candidate. Not a second hole.
