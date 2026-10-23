# Rubric review — Hermes control plane spine

Reviewer: rubric walker
Spine: `_bmad-output/planning-artifacts/architecture/architecture-Hermes-2026-10-18/ARCHITECTURE-SPINE.md`
Driving spec: `_bmad-output/planning-artifacts/prds/prd-Hermes-2026-10-17/prd.md` (FR-1–FR-25) plus `addendum.md`
Checked against the tree at this review, not against the addendum where the two disagree.
Date: 2026-10-19

## Verdict

**fix**

The spine is a real feature-altitude contract: one mutator, environment-blind scripts, gates in repository settings, prod never checks out a pull-request SHA, and the adopted brownfield rules are mostly ratified rather than redesigned. It is not safe to break into epics yet. AD-3 does not freeze the set of names the click writes into `$ROOT/.env`. GitHub cannot enumerate Environment secrets, so two epics will invent different lists. A partial file is what `build_runtime_env` copies onto the host, and that silently strips optional integrations on prod. Four medium gaps are the same class of miss: a word two stories will define differently.

## Checklist

| Criterion | Result |
| --- | --- |
| Fixes the real divergence points for epics, and misses none that would let two epics build incompatibly | Fail. The CD shape is frozen. The secret projection, the snapshot trigger, the prod preflight transport, payload deletion, and what a green check attests are not. |
| Every AD Rule is enforceable and actually prevents its stated divergence | Fail on AD-3. AD-16 does not clearly bind the new preflight SSH. The other rules do what they claim. |
| Nothing under Deferred could let two units diverge | Pass. Every row has an interim freeze. The header rule ("do not implement the open choice inside a CD story") holds. |
| Named tech is verified-current, or explicitly a tree pin rather than a claim of latest | Pass. Stack is labeled "Tree pins, not a bump." `actions/checkout` v7.0.1 exists (released 2026-07-20). This repo stays on v4 as pinned in `pr-checks.yml`. `astral-sh/setup-uv` v5 is the same kind of pin. Firecrawl images are explicitly the floating tags already in `firecrawl/docker-compose.yml`, not a new "latest" claim. |
| Ratifies rather than contradicts the brownfield codebase | Pass with one soft miss. Paths, pair gates, loopback binds, patch survival, health fail-closed set, and `scp_cmd`'s missing `BatchMode` match the tree. "If snapshot is configured" does not match how skill and cron push decide to refresh. |
| Covers FR-1 through FR-25 | Pass on mapping. Every FR is in `binds` and in the capability map, and the load-bearing consequences have an AD. FR-19's timezone-mismatch warning is the only consequence left unnamed. The FR-25 filter requirement is stated, but the input set to that filter is not, which is finding 1. |
| Every feature-altitude dimension is decided, deferred, or an open question | Pass. Deployment and environments, infra and provider, and operations are decided (two hosts, GitHub-hosted runner, no provisioner, no rollback, no uptime target, logs named, concurrency named). Open Questions 1–6 are deferred with freezes. Host sizing is only a clause inside the non-goals row, which is enough to stop a story from adding a sizer. |
| No template comments, no placeholders | Pass. No HTML comments, no `{name}` leftovers, no TBD. "placeholdered" in AD-8 is a real instruction, not a template token. |

## Findings

### 1. High — the click's secret projection is not a closed set

- **Where:** AD-3. Also AD-2, AD-8, FR-3, FR-24, FR-25.
- **Prevents claimed:** a job that holds both secret sets, a host input, an environment-name input, or a workflow-hardcoded snapshot prefix.
- **What it does not prevent:** two epics materializing different subsets of the operator contract into the one `.env`.

AD-3 says the runner writes one mode-600 `$ROOT/.env` from exactly one GitHub Environment, and that secret names match variable names, with `SSH_PRIVATE_KEY` as the only rename. That freezes the mapping and the "one set" rule. It does not freeze the set.

GitHub Actions cannot dump an Environment. Each name has to be written out in the workflow. `.env.sample` is a long contract: required deploy and Telegram keys, plus optional Discord, Notion, S3, home-channel, voice, Exa, `GITHUB_TOKEN`, `TIMEZONE`, `SSH_PORT`, `REMOTE_DIR`. A CD epic that passes only the five `require_vars` names, and a secrets epic that passes every name `build_runtime_env` copies, both satisfy AD-3 as written.

That is incompatible in production, not just in style. `scripts/deploy.sh` replaces the host runtime env from that file. Keys `build_runtime_env` copies only if set — Discord, Notion, AWS/S3, home channel, `GITHUB_TOKEN`, voice — disappear from the host when the click omits them. `TIMEZONE` falls back to `Asia/Dubai`. Prod and the environment sandbox then diverge from the operator's secret set, and from each other if the two workflows list different names. FR-25's "same filter" requirement assumes the filter's input is the environment's secret set, not a curated subset.

`S3_PREFIX` and `TIMEZONE` are called out. That makes the gap worse: a story can treat those two as the only extras.

- **Disposition:** autofix. In AD-3, freeze the projection: the workflow lists every name in `.env.sample` that `deploy.sh` or `build_runtime_env` reads, under the same name, from that one Environment. A name is omitted only when that secret is unset. It is not a required-only subset. `ALLOW_LOCAL_TARGET` and `PIN_CRON_FORCE` stay unset even if someone stored them. The only rename remains `SSH_PRIVATE_KEY` to a temp file passed as `SSH_IDENTITY_FILE`. Unset optional pairs stay unset so the pair gates still turn those features off.

### 2. Medium — "snapshot is configured" is two predicates

- **Where:** AD-13 and AD-14. Binds FR-15, FR-17.
- **Tree:** full deploy starts a snapshot only when `S3_BUCKET`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_DEFAULT_REGION` are all set (`scripts/deploy.sh` around the full-deploy tail). Skill push and cron push call `deploy.sh --s3-snapshot` when `S3_BUCKET` is set alone (`scripts/skills-push.sh`, `scripts/cron-push.sh`). The snapshot script then requires all four and the push warns if that fails. Skills or jobs are already on the host.
- **Divergence:** AD-13 correctly freezes the full-deploy gate (all four). AD-14 says "If snapshot is configured, skill push refreshes it" and does not define configured. One epic will align skill push with the all-four gate and skip the call. Another will keep the `S3_BUCKET` trigger and the warn-not-fail behavior. Both can cite an AD. Cron push has the same split and is not even named in that sentence.

This is also the brownfield miss. AD-14 is tagged `[ADOPTED]`. The adopted behavior is the `S3_BUCKET` trigger plus a warn, not "configured" in the AD-13 sense.

- **Disposition:** autofix. In AD-14, name both predicates: skill push and cron push attempt a refresh when `S3_BUCKET` is set; a snapshot failure warns and does not fail the push. Full deploy still starts a snapshot only when all four are set. Do not unify them in a CD story.

### 3. Medium — the prod preflight is a new SSH that AD-16 does not bind

- **Where:** AD-6 and AD-16. Binds FR-25, NFR-4.
- **Tree:** `ssh_cmd` in `scripts/deploy.sh` sets `BatchMode=yes` and `StrictHostKeyChecking=accept-new`. `scp_cmd` sets neither. That part of AD-16 is accurate, and "close that gap before the click is real" is the right CD task.
- **Divergence:** AD-6 puts the prod venv check outside `deploy.sh`, before `make deploy`. That check is the first SSH a prod click makes, and it does not exist yet. AD-16's "every deploy SSH" can be read as `deploy.sh` only, because the next sentence is about `scp_cmd`. One story will probe with `BatchMode=yes` and `accept-new`. Another will use a raw `ssh`, or an action that prompts. The stated prevent — a CD job hanging on a password or host-key prompt — is exactly this new step. AD-6 also does not say the preflight must not print the remote env or the key.

- **Disposition:** autofix. In AD-16, name the prod preflight as deploy SSH: same `BatchMode=yes` and `StrictHostKeyChecking=accept-new`, no host-key prompt, no secret echo. It still does not live inside `deploy.sh`.

### 4. Medium — payload sync is an overlay, and the paradigm says the ref is the desired state

- **Where:** Design Paradigm, Structural Seed, AD-14.
- **Tree:** `scripts/deploy.sh` rsyncs `scripts/lib`, `scripts/remote`, `config`, `firecrawl`, `artifacts`, and `extensions` with no `--delete`. Artifact install skips a missing seed file and does not erase the host copy (`scripts/remote/install-artifacts.sh`). That is why a runner checkout, which has no skill bodies and no seeds, does not wipe them. AD-14 freezes the artifact half ("Artifact sync does not use `--delete`"). It does not freeze the payload half.
- **Divergence:** the paradigm says desired state is one git ref plus one secret set. A CD epic can add `--delete` to the script and config rsync so a removed file actually leaves the host. A ratifying epic will leave the overlay. Those clicks do not converge. Adding `--delete` to artifacts would also violate AD-14 and would wipe seeds on a runner checkout, so the freeze has to stay split: artifacts and seeds stay an overlay; whether scripts and config are a mirror is the open call.

Do not silently pick the mirror. `--delete` on `scripts/` would change laptop deploy too, because both clicks and the laptop share `deploy.sh`.

- **Disposition:** autofix the freeze, do not redesign the sync. State that payload rsync does not use `--delete`, a CD story does not add it, and a file removed from the ref can remain on the host until an operator deletes it. Artifact sync stays no `--delete`, which is already said. If a later decision wants the ref to be a true mirror, that is a separate change to `deploy.sh`, not something an epic infers from the paradigm sentence.

### 5. Medium — "pr-checks.yml success for that SHA" does not say which tree was tested

- **Where:** AD-5. Binds FR-21, FR-25, UJ-4.
- **Tree:** `.github/workflows/pr-checks.yml` triggers on `pull_request` and checks out with `actions/checkout@v4` and no `ref`. That checkout is the pull-request merge ref, not the head SHA. The check run is still associated with the head SHA.
- **Divergence:** AD-5 requires `pr-checks.yml` success for the head SHA, then checks out that head SHA. Both of these readings comply:
  - the workflow run for that head SHA concluded success (current association; the job may have executed the merge ref);
  - the job must have checked out and tested that exact SHA (which means changing `pr-checks.yml`).

  One epic will retarget `pr-checks.yml` to `github.event.pull_request.head.sha` so the attested tree matches the click. Another will leave the workflow alone and treat a green conclusion as enough. Sandbox then either deploys a SHA CI did not execute, or CI starts testing a different tree than it does today. AD-5's prevent ("sandbox deploying the wrong revision") does not decide this. Prod is unaffected: it checks out `master` only.

- **Disposition:** autofix. Freeze the adopted reading: success means the `pr-checks.yml` workflow run for that same-repo pull request's head SHA concluded success. Do not retarget that workflow's checkout in the CD change. The sandbox click still checks out the head SHA, not the merge ref. The residual — CI may have executed the merge ref — stays accepted until a separate decision. Also name the job file, which the rule already does, so a story does not invent a second required check.

### 6. Low — FR-19's timezone mismatch is not in the warning set

- **Where:** AD-19 and the State row in Consistency Conventions.
- **Spec:** FR-19 lists timezone mismatch with the other visible warnings (search/extract, Mnemosyne, Agent-Reach, half-configured Notion). It is not an exit failure.
- **Tree:** `scripts/remote/healthcheck.sh` warns when `TIMEZONE` in the runtime env does not match the host clock, and does not set `failed`.
- **Divergence:** AD-19's exit list is closed, so a story should not fail the deploy on timezone. It does not say the mismatch must be a visible warning rather than a silent pass. Half-configured Notion is named. Timezone is not. Two health stories can drop the warning or keep it.

- **Disposition:** autofix. Add timezone mismatch to the "visible warning, not an exit failure, not a silent pass" sentence. Health still does not apply timezone.

### 7. Low — "patch cannot be reapplied" is broader than the healthcheck

- **Where:** AD-19. AD-10 is the accurate sentence.
- **Tree:** if `docker.py` is absent, health warns and continues (`healthcheck.sh`, "docker.py not found (skip patch check)"). It exits non-zero only when the file exists, the marker is missing, and reapply fails. FR-19 says the same: fail when the marker is missing and the patch cannot be reapplied.
- **Divergence:** a story that reads AD-19's fail list literally will fail health when `docker.py` is missing. That contradicts the tree and AD-10.

- **Disposition:** autofix. Exit non-zero only when the marker is missing and reapply fails. A missing `docker.py` stays a warning.

## What held

These were checked because they looked like contradictions, and they are not findings.

- AD-12's "health refuses if the Telegram token or allowlist is missing" matches `scripts/deploy.sh`: `require_vars` runs before the health branch. The addendum's "every mode except health" line is stale. The spine follows the code and FR-7.
- AD-6's two venv paths match `scripts/remote/bootstrap.sh`. The consistency note that the prod preflight is stricter than the installer skip is right: bootstrap also skips when `hermes` is already on `PATH`.
- AD-9's `ALLOW_LOCAL_TARGET` exact `1` matches `refuse_local_target`. Any other value, including `true`, still refuses.
- AD-10's reapply-on-bootstrap, config push, and control-plane upgrade, and health's marker-only reapply from the copy already on the host, match the scripts. The patch script no-ops when the marker is present, so NFR-6's "not applied twice" is not contradicted by "reapply".
- AD-11 loopback binds match `firecrawl/docker-compose.yml` (`127.0.0.1:8888` and `127.0.0.1:3002`). `FIRECRAWL_MODE` is not written by `build_runtime_env`.
- AD-14 artifact overlay matches `install-artifacts.sh` (missing seed is a skip, not a delete). A runner `make deploy` will not wipe seeds. That interaction with AD-6 ("do not call seed push") is sound and should stay.
- AD-19's fail set matches the healthcheck for Hermes, Docker, runtime env, config, `USER.md`, gateway process (status failure plus no process), and `yt-dlp` when the Agent-Reach image is present. Half-configured Notion is a warning, not an exit, which matches the script and FR-19, and resolves FR-14's looser "fails a default-stack check".
- Deferred rows for Open Questions 1–6, the actor allowlist, pinned `known_hosts`, a native pull-request button, voice, other gateways, other providers, firewall, fail2ban, spend watch, and webhook mTLS all forbid the opposite implementation. None of them leave a live choice for two epics.
- Feature altitude owns deployment, environments, provider, and operations. Those are decided: GitHub-hosted `ubuntu-latest`, two GitHub Environments, no provisioner, no destroy, no rollback, no uptime target, journal plus `~/.hermes/logs/gateway.log`, one deploy at a time per environment. Not a silent dimension.
- No parent spine is inherited. No inherited-AD check applies.

## Not a finding

Running the checked-out pull-request SHA's `make deploy` with sandbox secrets is an accepted leak of the sandbox set. AD-5 plus AD-6 already force that reading (checkout that SHA, then `make deploy`, and prod never checks out a pull-request SHA). A story that "secures" the click by executing master's `deploy.sh` against a side checkout would violate "sandbox deploying the wrong revision". No extra rule is required unless finding 5's freeze is dropped.
