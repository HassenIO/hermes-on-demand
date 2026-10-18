---
title: Hermes control plane
status: draft
created: 2026-10-17
updated: 2026-10-18
---

# PRD: Hermes control plane

Working title. The repo is Hermes. The product in this document is the control plane, not upstream Hermes Agent.

## 0. Document Purpose

This PRD is the requirements baseline for the Hermes control plane: the repository that stands up, configures, upgrades, and publishes a private Hermes Agent on an Ubuntu agent host. It is not a PRD for upstream Hermes Agent. Today the operator runs it from a laptop. The recommended next path is a CD pipeline: a click deploys the environment sandbox after pull-request checks succeed, and a separate click deploys prod only after merge to master. Neither click is automatic. That pipeline is not in the tree yet. It is for the operator, for a collaborator changing the repo, and for downstream architecture and story work. It is not a runbook. Operator steps stay in `README.md` and `docs/`. Mechanism, conflict log, and file inventories live in `addendum.md`.

The shape is a brownfield capability spec. Section 6 is current scope, not a greenfield MVP cut, because the system already exists. Aside from the named CD capability in §4.14, this PRD captures the current intended product, not a roadmap of unbuilt work. User journeys are short operator and replicator scenes, not a UX spec. Requirements are what the product must keep true. Where `README.md` and the code disagree, this PRD follows the enforced contract. Those conflicts are listed in the addendum, not smoothed over here.

## 1. Vision

Hermes Agent is a self-hosted agent. Upstream expects the operator to install it on the machine that will run it, put secrets in a runtime env file, and own updates. It does not ship a remote control plane, a filter that keeps laptop-only settings off the agent host, or a publishable way for a stranger to repeat the setup without inheriting someone else's tenants.

This repo is that missing control plane. One person, from a checkout that never becomes the agent, can stand up a private Telegram gateway on a VPS they already have, change model, secrets, and profile seeds without SSH surgery, and survive an upstream upgrade without losing the sandbox fix Telegram needs. Today that person runs the commands on a laptop. That stays an exception for an atomic test, not the recommended path. The recommended path is a click: environment sandbox from a pull request after checks succeed, prod only after merge to master. Neither deploy fires by itself. A second person can clone the repo and do the same with their own host, key, and bot, because secrets, skill bodies, cron jobs, and profile seeds are not in git.

The bet is narrow. The danger is not the model. It is a committed `.env`, an allow-all bot with a terminal, a public extract port, an upgrade that clobbers the colon-path fix, or a Notion page id baked into the tree. The product is successful when those stay hard to do by accident, and when a collaborator can change the control plane through a branch and a pull request without a live agent host in CI.

What this gives up: two named environments, not a fleet. Telegram is required for a first deploy, even if the operator also wants Discord. The supported model provider is OpenRouter. A clone inherits `Asia/Dubai` and the model pin in the config example. Those are the published defaults. A replicator changes them before deploy if they are not theirs. There is no license file yet, so "safe to share" is a requirements bar, not a claim that the tree is already publishable.

## 2. Target User

Two people, sometimes the same person: the operator who runs one instance, and an outside replicator or collaborator.

### 2.1 Jobs to be done

- Stand up one private agent on a VPS I already have, from this checkout, without installing Hermes on the laptop.
- Deploy the environment sandbox from a pull request, after checks succeed, by clicking. Deploy prod only after merge to master, by a separate click. Neither deploy is automatic. Prod stays up. The environment sandbox may be destroyed between runs.
- Change model, secrets, or profile seeds and resume chat, without hand-editing the agent host.
- Upgrade upstream Hermes without breaking Telegram sandboxes or wiping the extensions that must survive that upgrade.
- Publish the control plane so a stranger can replicate it and a collaborator can change it, without inheriting my tokens, tenant ids, skill bodies, or unsafe defaults.
- Prove a control-plane change with local lint and unit tests, not with a live gateway in CI.

### 2.2 Non-users (v1)

- Someone who wants Hermes installed on the control-plane machine.
- Someone who wants a public or community bot, or `GATEWAY_ALLOW_ALL_USERS` / `DISCORD_ALLOW_ALL_USERS` as the default.
- Someone who wants a hosted "no VPS" product, a VPS provisioner, or a multi-tenant service.
- Someone who wants a gateway other than Telegram, plus optional Discord, as the default surface. Upstream supports many platforms. This product does not.
- A team sharing one snapshot prefix, or a shared host where applying `Asia/Dubai` by default would be a surprise they cannot override.

### 2.3 Key user journeys

Journeys are light on purpose. This is an operator tool, not a consumer UI. Each one names the person and the done state a story can test.

**UJ-1. Hassen stands up a new agent host.**

Hassen has a fresh Ubuntu VPS, an SSH key, passwordless sudo, an OpenRouter key, and a private Telegram bot. The control plane is a local checkout. Hermes is not installed on the laptop. He copies the env sample, fills host, user, key, bot token, and allowlist, and runs the full deploy. Health passes. He messages the bot, sends `/new`, and asks what it knows about him. The reply reflects the seeds. A person not on the allowlist is not accepted. If the token is already bound to another gateway, he revokes it and retries. He does not install Hermes locally to debug.

**UJ-2. Hassen rotates a secret and changes the model.**

The gateway is already running. Hassen edits the local env and the config example, pushes config, and sends `/new`. The new session uses the new model. A cron job that already named a different model is left alone. A Telegram session id that contains a colon still gets a sandbox. He does not SSH in to patch Docker or edit cron by hand.

**UJ-3. Sam replicates the repo.**

Sam clones the public tree. There is no `.env`, no skill bodies, no cron file, and no Hassen tenant id. Sam copies the env sample, fills their own host, key, and allowlist, and deploys. Their bot answers them. If they set only one Notion variable, Notion stays off rather than half-configured. They still have to notice the published timezone default and model pin and change them if those are not theirs.

**UJ-4. Sam proposes a control-plane change.**

Sam branches off master. They do not push to master. Lint and unit tests pass locally. Pull-request checks run the same two checks and comment on the pull request. The pull request contains no tokens. A change that would make an existing env file or Make invocation do the wrong thing is marked breaking. When the checks succeed, a sandbox deploy click appears. Sam clicks it. The environment sandbox updates. Prod is not offered, and nothing deployed itself when the checks went green.

**UJ-5. Hassen deploys to the environment sandbox, then to prod.**

Hassen does not use the laptop unless he is doing an atomic test. On a pull request, after checks succeed, he clicks sandbox deploy. Prod is unchanged, and the click was required. He merges to master. Prod does not deploy on the merge. He clicks prod deploy. The gateway is still running afterward. He can destroy the environment sandbox between runs. That does not take prod down. Neither run installs Hermes on the laptop or on the CD runner.

## 3. Glossary

Downstream work uses these terms. No synonyms.

- **Control plane** — this checkout, whether the operator runs it on a laptop or a CD runner executes it. Deploy and edit only. Never a Hermes runtime.
- **Agent host** — the remote Ubuntu machine where Hermes runs. Docs call it the VPS. This PRD says agent host.
- **Environment** — a named deploy target. This product has two: `prod` and `sandbox`. They are separate agent hosts, with separate secrets, bot tokens, and snapshot prefixes. An environment sandbox is not the Sandbox. The environment sandbox is trashable and is where a first deploy or an update is tested. Prod is the important environment. A deploy there is an update, not a teardown.
- **CD pipeline** — the runner that deploys one environment when the operator clicks. It is a control plane, not an agent host. Pull-request checks are not a deploy. A click after those checks succeed may deploy the environment sandbox. A click after merge to master may deploy prod. Neither click fires by itself.
- **Payload** — the copy of scripts and templates on the agent host (`~/hermes-setup/` today). Not the runtime.
- **Runtime** — `~/.hermes/` on the agent host: env, config, logs, skills, cron, memory. The runtime env file is the filtered secret file inside the runtime.
- **Gateway** — the one user service, `hermes-gateway`, that runs Telegram and optional Discord in one process.
- **Linger** — the user service survives logout and starts at boot.
- **Allowlist** — the set of messaging user ids permitted to talk to the gateway. Deny-by-default means an absent allowlist admits nobody. This product requires a Telegram allowlist before deploy.
- **Allow-all** — a flag that admits every sender. Forbidden as a published default. Not the same as an empty allowlist.
- **Seed** — a profile file in `artifacts/` copied to the agent host. Not the live memory store.
- **Skill** — a directory with `SKILL.md` frontmatter `name`, `description`, and `version`. This repo pushes custom skills only. Builtins are not in the tree.
- **Cron job** — an object in the jobs file with a unique `id`, a `name`, and a `schedule`. Names need not be unique. Push replaces the remote set.
- **Model drift** — the gateway's default model changed and a cron job was not pinned, so the job refuses to run. A job that already names a different model is left alone when the default changes.
- **Snapshot** — a one-way mirror of custom skills and the jobs file to object storage, plus a watcher. Not a backup. Not a restore.
- **Sandbox** — the Docker terminal the agent uses. Not the host shell. The default image is the Agent-Reach image unless that extension is skipped.
- **Session-path patch** — the required correction that lets a Telegram session id containing `:` resolve to a valid sandbox path. Upstream upgrade can wipe it. The control plane must put it back.
- **Half-configured** — exactly one of a required pair is set. Notion treats that as failure if it reaches the agent host. Discord treats a half pair as off and forwards nothing.
- **Home channel** — the single destination for proactive and cron delivery. Optional.
- **Collaborator** — a person changing the control plane through a branch and a pull request. A replicator is a person deploying their own agent host from a clone. One person can be both.
- **Published contract** — Make targets, `.env.sample`, and `config/config.yaml.example`. A change that makes an existing env file or Make invocation do the wrong thing is breaking.

## 4. Features

### 4.1 Stand up one agent host

**Description:** A full deploy from the control plane installs Hermes on the agent host, starts the gateway with linger, applies timezone, brings up the default stack, and ends in a health check. The control plane machine is refused as a target. Realizes UJ-1.

**Functional requirements:**

#### FR-1: Bootstrap one agent host

The operator can bootstrap a fresh Ubuntu agent host from the control plane in one command, given SSH key access, passwordless sudo, an OpenRouter key, a Telegram bot token, and a Telegram allowlist. Realizes UJ-1.

**Consequences (testable):**

- A target of `localhost`, `127.0.0.1`, or `::1` fails before SSH unless `ALLOW_LOCAL_TARGET` is set. That override is not part of the published contract and must not appear in `.env.sample` as a recommended setting.
- Deploy SSH does not prompt for a password.
- Hermes is installed on the agent host only, with the browser component skipped.
- After success, the gateway is running as a user service and linger is enabled.
- Timezone comes from `TIMEZONE`. If unset, `Asia/Dubai` is applied. Health does not apply timezone.
- A successful full deploy ends in a health check the operator can re-run later without uploading a new payload.
- Re-running bootstrap on a host that already has the Hermes venv does not run the installer again. Re-running still rewrites the runtime env and config and restarts the gateway.

**Out of scope:**

- Provisioning the VPS, opening firewall ports, or installing Hermes on the control plane.

#### FR-2: Optional stack gates

Optional pieces have explicit on/off rules. Skip flags apply only to a full deploy, not to a dedicated setup command. Realizes UJ-1, UJ-3.

**Consequences (testable):**

- On a full deploy, web search/extract, Mnemosyne, and Agent-Reach run unless their skip flag is set. Notion runs only when both Notion variables are non-empty. Snapshot runs only when all four AWS/S3 variables are set.
- A dedicated setup command still syncs payload and applies timezone even when its own install is skipped. That preamble is intended. A skipped install is not a full no-op.
- There is no skip flag for Notion. Absence of the pair is the off switch.
- `SKIP_*` never appears in the runtime env.

### 4.2 Deliver configuration and secrets

**Description:** Secrets stay in the operator's local env file. A filter writes the runtime env. Control-plane-only variables never reach the agent host. Behavior lives in the config example, not in env. Realizes UJ-2, UJ-3.

**Functional requirements:**

#### FR-3: Secret filter

The control plane writes a runtime env that contains only variables the agent host is allowed to have. The runtime env file mode is `600`. Realizes UJ-2, UJ-3.

**Consequences (testable):**

- After a config push, the runtime env does not contain `TARGET_*`, `SSH_*`, `SKIP_*`, `REMOTE_DIR`, `ALLOW_LOCAL_TARGET`, `PIN_CRON_FORCE`, `FIRECRAWL_MODE`, or `LLM_MODEL`.
- The model the gateway uses is `model.default` in the config file. `LLM_MODEL` is not a supported way to set it. The published config does not pin Sonnet.
- `.env.sample` and the config example contain placeholders only. No live token, no tenant id.
- API keys are not placed in the config example.

#### FR-4: Push config and rotate secrets

The operator can push config or rotate a secret without a full reinstall. The gateway restarts. A new session sees the change after `/new`. Realizes UJ-2.

**Consequences (testable):**

- Config push writes the runtime env and config, reapplies the session-path patch, relinks the `hermes` command, restarts the gateway, and pins cron jobs.
- Config push does not upload the jobs file. Cron push is a separate command.
- Config push does not prompt for a password, and it refuses the control-plane machine the same way a full deploy does.
- A broken `hermes` command is repaired by relinking to the venv binary. `hermes doctor --fix` is not the repair path.

#### FR-5: Pair gates and allow-all defaults

Discord and Notion are all-or-nothing. Allow-all is never a published default. Realizes UJ-3.

**Consequences (testable):**

- If only one of `DISCORD_BOT_TOKEN` and `DISCORD_ALLOWED_USERS` is non-empty, the runtime env contains no `DISCORD_*` variables. An empty string counts as unset.
- If only one of `NOTION_API_KEY` and `NOTION_REPORTS_PARENT_PAGE_ID` is non-empty, the runtime env contains no `NOTION_*` variables and the Notion CLI is not installed.
- `.env.sample` and the config example do not set `GATEWAY_ALLOW_ALL_USERS` or `DISCORD_ALLOW_ALL_USERS` to true.
- A pull request that sets either allow-all flag true in a published default is a breaking safety defect.

**Notes:**

- [NOTE FOR PM] The filter copies allow-all if the operator sets it, including `true`. Upstream supports the flag. OSS safety cares first about what a stranger copies. Refusing an explicit true would also block an operator who set it on purpose. See Open Question 1.

### 4.3 Profile seeds

**Description:** SOUL, USER, MEMORY, and CV are seeds the operator can roll back from the control plane. Built-in memory injection stays off so seeds are not applied twice. Realizes UJ-1, UJ-2.

**Functional requirements:**

#### FR-6: Update seeds

The operator can update seeds and have a new session reflect USER and MEMORY without the agent reading those files itself. CV is available on demand, not injected every turn. Realizes UJ-2.

**Consequences (testable):**

- USER and MEMORY entries are separated by a line containing only `§`.
- `memory_enabled` and `user_profile_enabled` remain false after a deploy or memory setup.
- CV is mounted read-only. It is not part of the every-turn injection.
- Seed push syncs payload, applies timezone, and restarts the gateway. That is the contract, even where a README line says "seeds only."
- Seeds are not committed. Each of `artifacts/`, `skills/`, and `cron/` may commit a `README.md` only.

### 4.4 Messaging

**Description:** Telegram long-poll is the required surface. Discord is optional on the same gateway. No inbound port is required for either default. Realizes UJ-1, UJ-3.

**Functional requirements:**

#### FR-7: Telegram deny-by-default

A first deploy requires a Telegram bot token and a Telegram allowlist. The gateway uses long-poll. Realizes UJ-1.

**Consequences (testable):**

- Deploy, config push, seed push, update, and health all refuse to start if the Telegram token or allowlist is missing from the operator env.
- The control plane does not evaluate the allowlist. It requires the variables and forwards them. Admission is the gateway's job.
- Default Telegram and Discord need no inbound port on the agent host.
- Webhook mode is not the default and is not configured by this control plane.

#### FR-8: Discord stays off unless paired

Discord runs in the same gateway process only when both the bot token and the allowlist are non-empty. Sessions do not merge with Telegram. Realizes UJ-3.

**Consequences (testable):**

- A half pair forwards no Discord variables (FR-5).
- Health reports Discord only when both values are already in the runtime env.
- Discord portal intents (Message Content, Server Members) are an operator precondition. The control plane does not click through the Discord portal.
- One home channel is the proactive destination. It is optional. A second home channel is out of scope.

#### FR-9: Home channel

The operator can name one home channel for proactive and cron delivery. If unset, proactive delivery has no control-plane default. Realizes UJ-1.

**Consequences (testable):**

- Home-channel variables are forwarded only when set.
- Telegram and Discord home channels are independent. They do not cross-post.

### 4.5 Web search and extract

**Description:** Default search is a local SearXNG. Default extract is local Firecrawl in lite mode. Both bind to loopback. Realizes UJ-1.

**Functional requirements:**

#### FR-10: Loopback search and extract

A full deploy starts search and extract on loopback unless the operator skips them. Realizes UJ-1.

**Consequences (testable):**

- Default bind is `127.0.0.1` for both services. Publishing either off loopback is a defect.
- Default extract mode is lite. Full mode is an explicit opt-in for a larger host and is not written into the runtime env.
- Skip applies only to a full deploy (FR-2). A dedicated setup command always installs them.
- A cloud extract key may be forwarded if set. It does not replace the loopback bind of the local services.

### 4.6 Memory

**Description:** The default memory provider is Mnemosyne, installed so an upstream upgrade does not wipe it. Built-in injection stays off. Realizes UJ-1.

**Functional requirements:**

#### FR-11: Mnemosyne survives upgrade

A full deploy installs Mnemosyne as the memory provider unless skipped. An upgrade through the control plane refreshes that install if it is already present. Realizes UJ-1, UJ-2.

**Consequences (testable):**

- `memory.provider` is `mnemosyne` after setup.
- `memory_enabled` and `user_profile_enabled` are false (FR-6).
- The provider recorded in config is OpenRouter after Mnemosyne setup. OpenRouter is the only supported provider. Other providers are out of scope.
- Skip applies only to a full deploy. If the side install already exists, upgrade refreshes it.

### 4.7 Sandbox

**Description:** The agent's terminal is a Docker sandbox. Telegram session ids contain a colon. The session-path patch is what keeps those ids working, and it must survive upgrade. AWS keys must not enter the sandbox. Realizes UJ-2.

**Functional requirements:**

#### FR-12: Session-path patch survives the paths that upgrade

After bootstrap, config push, and an upgrade performed through the control plane, a Telegram session id containing `:` can start a sandbox. Realizes UJ-2.

**Consequences (testable):**

- Bootstrap, config push, and control-plane upgrade reapply the session-path patch.
- Health reapplies it only when the marker is already missing, using the copy already on the agent host. Health does not upload a new patch.
- A bare upstream update is not a supported operator path. Docs and the operator contract say so.
- `AWS_*` is not in the sandbox forward list. AWS keys may exist in the host runtime env for snapshot. They must not be added to `terminal.docker_forward_env`.

#### FR-13: Default sandbox image

On a full deploy, the default sandbox image is the Agent-Reach image unless that extension is skipped. `GITHUB_TOKEN` may be forwarded into the sandbox when set. Realizes UJ-1.

**Consequences (testable):**

- Skip applies only to a full deploy (FR-2).
- If the image or the skill is already present, control-plane upgrade refreshes it.
- Cookie-based platform logins, and platforms the Agent-Reach docs exclude, are not required for a successful deploy.

### 4.8 Notion reports

**Description:** Notion is an optional REST CLI and skill, not an MCP server. Both variables are required. Page ids stay in env. Realizes UJ-3.

**Functional requirements:**

#### FR-14: Notion all-or-nothing

Notion is installed only when both `NOTION_API_KEY` and `NOTION_REPORTS_PARENT_PAGE_ID` are non-empty. The control plane disables Notion MCP. Realizes UJ-3.

**Consequences (testable):**

- A half pair does not install the CLI and does not write Notion variables (FR-5).
- Health fails a default-stack check if Notion is half-configured on the agent host.
- No Notion page id appears in the config example, `.env.sample`, or any committed file. Optional extra page ids stay in the operator env.
- A neither-var setup command still syncs payload and applies timezone, then exits success without installing Notion.

### 4.9 Skills and cron

**Description:** Custom skills and cron jobs move between the control plane and the agent host on purpose. Direction matters. The agent host is the copy to keep only when the operator pulls. Realizes UJ-2, UJ-4.

**Functional requirements:**

#### FR-15: Skill sync direction

Skill push mirrors custom skills to the agent host, prunes remote custom packages that are missing locally, and excludes `README.md`. Skill pull replaces the local skill tree and is only for when the agent host is the copy to keep. Realizes UJ-4.

**Consequences (testable):**

- Builtins are not in the control-plane tree and are not pushed.
- Skill bodies are gitignored. A clone does not contain them.
- If snapshot is configured, skill push also refreshes the snapshot.
- Skill push and skill pull do not refuse the control-plane machine. See Open Question 5.

#### FR-16: Cron sync and model pin

Cron pull overwrites the local jobs file. Cron push replaces the remote set after validation. A model change pins unpinned jobs through config push, and leaves a job alone when it already names a different model. Realizes UJ-2.

**Consequences (testable):**

- A job missing a unique `id`, a `name`, or a `schedule` is rejected. Duplicate names are accepted.
- The jobs file contains no tokens.
- `PIN_CRON_FORCE` is not forwarded to the runtime env. Forcing the pin is an on-host action, not a control-plane env variable.
- Config push does not upload the jobs file (FR-4). Cron push does not restart the gateway.
- The local jobs file written by pull is mode `600`.

### 4.10 Snapshot

**Description:** When object storage is configured, custom skills and the jobs file are mirrored one way. Sessions, secrets, and databases are not. The bucket must already exist. The control plane does not prove it is private. Realizes UJ-3.

**Functional requirements:**

#### FR-17: Snapshot scope

Snapshot uploads custom skills, the jobs file, and a manifest. It does not upload SQLite, sessions, logs, the runtime env, or builtins. Realizes UJ-3.

**Consequences (testable):**

- The four AWS/S3 variables must all be set or snapshot does not run on a full deploy.
- The control plane does not create the bucket. If the bucket is missing, snapshot fails.
- An empty custom-skill tree does not delete remote skill objects.
- Snapshot does not restart the gateway.
- Objects are server-side encrypted.
- The control plane does not check that the bucket blocks public access. The operator must pre-create a private bucket. [NOTE FOR PM] See Open Question 4.
- One writer per prefix. Multi-writer is out of scope.
- Snapshot is not a restore. There is no control-plane command that pulls snapshot objects back onto an agent host.

### 4.11 Upgrade and health

**Description:** Upgrade goes through the control plane so the session-path patch, present extensions, and cron pin survive. Health inspects the agent host without uploading a new payload. Realizes UJ-2.

**Functional requirements:**

#### FR-18: Upgrade through the control plane

The operator upgrades Hermes through the control plane, not with a bare upstream update. Realizes UJ-2.

**Consequences (testable):**

- Control-plane upgrade reapplies the session-path patch, restarts the gateway, and pins cron.
- If Mnemosyne, Agent-Reach, or Notion is already present, upgrade refreshes that piece. It does not install a piece that was never set up.
- After upgrade, UJ-2's colon session id still gets a sandbox (FR-12).

#### FR-19: Health without upload

The operator can check the agent host without uploading a new payload, applying timezone, or restarting the gateway. Realizes UJ-1.

**Consequences (testable):**

- Health fails if Hermes, Docker, the runtime env, config, `USER.md`, or the gateway is missing, or if the session-path patch cannot be reapplied when the marker is missing.
- Health fails if the Agent-Reach image is present but its required media tool does not run.
- A missing default-stack piece that a full deploy should have installed (search/extract, Mnemosyne, Agent-Reach, half-configured Notion, timezone mismatch) is a warning the operator can see. It is not a silent pass.
- `hermes doctor` findings are non-fatal. Health must not run `hermes doctor --fix`.
- Health is not a first-time installer. On a host with no payload, it does not upload one.

### 4.12 Publish and collaborate

**Description:** The tree a stranger clones is safe to copy. The way a collaborator changes it does not require a live agent host and does not land on master. Realizes UJ-3, UJ-4.

**Functional requirements:**

#### FR-20: A clone inherits no secrets

A fresh clone contains no live secrets, no tenant ids, no skill bodies, no cron jobs, and no profile seeds. Realizes UJ-3.

**Consequences (testable):**

- `.env`, skill bodies, the jobs file, and artifact seeds are gitignored, and a unit test locks that ignore rule.
- `.env.sample` and the config example contain placeholders only (FR-3, FR-5, FR-14).
- Allow-all is not true in any committed default (FR-5).

**Notes:**

- [NOTE FOR PM] Timezone and the model pin are published defaults on purpose. A clone still also inherits author strings in scripts and docs. Those are not secrets. See Open Question 3.

#### FR-21: Change through a pull request

A control-plane change lands on a branch and a pull request into master. Pull-request checks run lint and unit tests only. Realizes UJ-4.

**Consequences (testable):**

- The contribution path is not a commit on master. There is no `develop` branch.
- Pull-request checks run shell syntax checks on `scripts/**/*.sh` and the unit-test suite with no env file loaded.
- Pull-request checks do not deploy, SSH, call the gateway, or talk to Telegram, Docker, or the network. They do not start the CD pipeline.
- The unit suite does not test the Notion CLI, and does not gain a unique-name check for cron jobs.
- Skill bodies, cron jobs, and artifact seeds are not committed, except each directory's `README.md`.

#### FR-22: Breaking changes are named

A change to the published contract that would make an existing env file or Make invocation do the wrong thing is marked breaking in the commit message. Realizes UJ-4.

**Consequences (testable):**

- The commit guideline names Makefile targets, deploy flags, and the env contract as breaking when behavior changes for an existing caller.
- The breaking-change trailer is the versioning policy. Semver tags are not required.

### 4.13 Long-form workspace

**Description:** Long-form genres are skills, not control-plane features. The control plane only has to leave a writable content workspace in place and not wipe it on config push. Genre skills, editorial stages, and model pins inside those skills are out of this PRD.

**Functional requirements:**

#### FR-23: Content workspace survives config push

The published config mounts a content workspace writable and the CV seed read-only. Pushing config must not drop those mounts. Realizes UJ-2.

**Consequences (testable):**

- After config push, the content workspace path is still mounted writable and the CV path is still mounted read-only.
- The control plane does not implement brief, research, outline, draft, verify, or publish. Those stages are skills.

### 4.14 Environments and CD

**Description:** Today the operator deploys from a laptop to one agent host. The recommended next path is a click in the CD pipeline. Prod is the important environment: a deploy there is an update of the existing system, not a teardown. The environment sandbox is trashable, and it is where a first deploy or an update is tested. Laptop deploy remains only as an exception for an atomic test. Nothing in the tree does the CD path yet. Realizes UJ-4, UJ-5.

**Functional requirements:**

#### FR-24: Two environments, prod durable

The operator can deploy to `prod` or to the environment sandbox. The other environment is unchanged. A prod deploy updates the existing system. It does not destroy it. The environment sandbox may be destroyed between runs, and it is the place to test a first deploy or an update. Realizes UJ-5.

**Consequences (testable):**

- Prod and the environment sandbox are separate agent hosts. They do not share a bot token, an allowlist, a runtime env, or a snapshot prefix.
- A deploy to one environment does not write the runtime env, config, or snapshot of the other.
- Destroying or recreating the environment sandbox does not stop the prod gateway.
- A prod deploy is an update of the existing prod system, not a destructive rebuild. Destroying the prod agent host is not a supported deploy.
- The CD runner and the laptop are refused as the agent host the same way the control-plane machine is refused today.
- Laptop deploy remains available for an atomic test, and the published contract calls it the exception, not the recommended path.

#### FR-25: Deploy on click, at the right gate

A sandbox deploy click is available on a pull request only after pull-request checks succeed. A prod deploy click is available only after that revision is merged to master. Neither deploy runs unless the operator clicks. Realizes UJ-4, UJ-5.

**Consequences (testable):**

- Pull-request checks do not SSH, do not hold environment secrets, and do not deploy.
- A green pull-request check does not deploy the environment sandbox by itself. The sandbox click is what deploys it.
- The sandbox click is absent, or refused, when pull-request checks have not succeeded.
- The prod click is absent, or refused, on an unmerged pull request. Merge to master does not deploy prod by itself.
- A click deploys exactly one environment. It does not deploy both.
- CD logs do not print secrets, tokens, or the runtime env.
- Environment secrets are not in git. The CD runner receives them outside the repo, and the same filter as FR-3 still drops control-plane-only variables.

**Notes:**

- [NOTE FOR PM] The previous draft called every CI deploy a non-goal, and then treated CD as a CLI the operator runs locally. Both are wrong. Pull-request checks still do not deploy. The sandbox click is part of the pull request, after those checks. The prod click exists only on master, after merge. CD is in scope and unbuilt.

## 5. Non-goals

- This product is not Hermes Agent, and not a fork of it. Upstream remains the runtime.
- No VPS provisioner, firewall manager, secrets manager, fail2ban, Docker network policy, or webhook mTLS.
- No hosted "no VPS" service and no multi-tenant control plane.
- No public or community bot. Allow-all is not a published default.
- No Hermes install, gateway, or sandbox on the control-plane machine.
- No inbound ports for default Telegram or Discord. Webhook mode is not the default.
- Search and extract are not published off loopback.
- Snapshot is not a backup of SQLite, sessions, logs, or secrets, and it is not a restore. The control plane does not create the bucket.
- The browser tool is not enabled. Notion MCP is not installed.
- Cookie-based social logins are not part of Agent-Reach in this product.
- Cron job names are not required to be unique. Do not add that validator check.
- Pull-request checks do not themselves deploy, and do not run health, SSH, Docker, or live Telegram tests. The Notion CLI is not in the PR suite. A later click may deploy the environment sandbox. That click is FR-25, and it is not built yet. An automatic deploy on green checks, or on merge, is a defect.
- Bare `hermes update` and `hermes doctor --fix` are not supported repair paths.
- Skill bodies, cron jobs, and profile seeds are not source-controlled.
- Voice is not a required surface. Voice keys may be forwarded if set. This PRD does not specify voice behavior.
- Gateways other than Telegram and optional Discord are out of scope, even though upstream supports them.
- A second memory provider, or a model provider other than OpenRouter, is out of scope.

## 6. Current scope

This section is the replicable surface that already exists. It is not a greenfield cut. Items below are in because the tree already commits to them, or out because a doc or a hard rule already excludes them.

### 6.1 In scope

- Full deploy, config push, seed push, health, upgrade, and dedicated setup commands for search/extract, memory, sandbox image, and Notion.
- Telegram required. Discord optional. Both deny-by-default.
- Loopback search and lite extract. Mnemosyne. Agent-Reach image. Session-path patch.
- Skill push/pull and cron push/pull, with model pin on config push.
- Snapshot of custom skills and the jobs file when AWS/S3 is fully set.
- Local lint, local unit tests, and the same two checks on every pull request.
- Gitignore of secrets, skills, cron, and seeds, locked by a test.
- Laptop deploy to one agent host. That is the only deploy origin in the tree today.

### 6.2 Out of scope for the current product

- Refusing an explicit allow-all flag in the filter. Documented ban only, until Open Question 1 is decided.
- Proving an S3 bucket is private. Operator precondition, until Open Question 4 is decided.
- Localhost refusal on `ssh`, skill sync, and cron sync. Deploy paths refuse it. The others do not. Open Question 5.
- A license and a contribution guide. Absent today. Open Question 2.
- Generalizing author name strings in scripts and docs before a public share. Timezone and the model pin stay as published defaults. Open Question 3.
- Loading `extensions/registry.yaml`. Nothing reads it. Registration is the deploy case and the Make target. Open Question 6.
- Treating today's single laptop target as two environments. The tree has one `TARGET_HOST`. Prod and the environment sandbox are the next capability (FR-24), not a description of the current script.
- Content-generation stages. Skills only (FR-23).

### 6.3 Intended next, not in the tree

- A disposable environment sandbox and a durable prod, on separate agent hosts (FR-24).
- A sandbox deploy click on a pull request after checks succeed, and a prod deploy click only after merge to master. Neither is automatic (FR-25).
- Laptop deploy documented as the exception for an atomic test, not the recommended path.

## 7. Success metrics

Hobby stakes, OSS bar. These are smoke checks a person can run, not dashboards.

**Primary**

- **SM-1:** Replication smoke. A stranger with their own host, key, and bot completes UJ-3. The allowlisted user gets a reply that reflects the seeds. A non-allowlisted user is denied. Validates FR-1, FR-7, FR-20.
- **SM-2:** Upgrade smoke. After a control-plane upgrade, a Telegram session id containing `:` still starts a sandbox. Validates FR-12, FR-18.
- **SM-3:** Publish smoke. A fresh clone has no `.env`, no skill bodies, no jobs file, no profile seeds, and no allow-all default. CI is green on lint and unit tests with no network. Validates FR-20, FR-21, FR-5.

**Secondary**

- **SM-4:** Secret rotation smoke. After a config push and `/new`, the new session uses the new model, and a cron job that already named a different model was not rewritten. Validates FR-4, FR-16.

**Counter-metrics (do not optimize)**

- **SM-C1:** Do not count a shorter command list as success if a safety gate was removed (pair gates, skip-flag scope, control-plane-machine refusal, loopback binds). Counterbalances SM-1.
- **SM-C2:** Do not count a green pull-request check as success if it deployed by itself, held a live token, or talked to an agent host. A later sandbox click is a different action. Counterbalances SM-3 and FR-25.
- **SM-C4:** Do not count a CD deploy as success if it deployed the environment the operator did not click, if merge alone deployed prod, if a sandbox rebuild stopped prod, or if the two environments shared a bot token or a snapshot prefix. Counterbalances FR-24, FR-25.
- **SM-C3:** Do not count snapshot completeness as success if secrets, sessions, or SQLite were uploaded, or if an empty skill tree deleted remote skills. Counterbalances the snapshot feature.

## 8. Cross-cutting NFRs

- **NFR-1:** The runtime env file, the local temp env, and the payload env copy are mode `600`.
- **NFR-2:** Search and extract listen on `127.0.0.1` only (FR-10).
- **NFR-3:** Default Telegram and Discord need no inbound port (FR-7).
- **NFR-4:** Deploy SSH from the control plane does not prompt for a password. Interactive `ssh` may.
- **NFR-5:** The operator can read gateway logs from the user journal and from the runtime log file. This PRD sets no retention period and no uptime target.
- **NFR-6:** Re-running a full deploy is safe on an already bootstrapped host: the installer is skipped if the venv binary exists, and the session-path patch is not applied twice. Config and the runtime env are still rewritten.

## 9. Constraints and guardrails

**Safety.** Messaging is deny-by-default. The published contract never enables allow-all. The sandbox is the boundary for the agent's terminal. The `docker` group on the agent host is root-equivalent. Do not widen the sandbox forward list without a skill that needs the variable inside the sandbox. `AWS_*` is excluded from that list. Do not run `hermes doctor --fix` to repair a broken `hermes` command.

**Privacy.** Seeds and the memory store stay on the agent host. Snapshot does not upload secrets, sessions, or SQLite. CV is not injected every turn. Tenant ids (Telegram user ids, Discord ids, Notion page ids) belong in the operator env, never in the repo.

**Cost.** The default stack is sized for a small VPS: 1–2 vCPU, 2 GB RAM (4 GB more comfortable), 20+ GB disk. Firecrawl full mode is not the default because it needs a larger host. No paid service is required beyond the VPS, OpenRouter, and a Telegram bot. Notion, S3, Exa, GitHub, and voice keys are optional. The control plane does not provision the VPS and does not watch spend.

## 10. Integrations and dependencies

The control plane depends on, and does not replace:

- Upstream Hermes Agent, installed on the agent host, including its gateway and its update command. The control plane wraps upgrade. It does not vendor the agent.
- Ubuntu 22.04 or 24.04 on the agent host, SSH key access, and passwordless sudo.
- OpenRouter as the model provider. A key is required.
- A Telegram bot and a numeric allowlist. Required.
- Docker on the agent host, for the sandbox and for search/extract.
- systemd user services and linger, for the gateway.

Optional, and off unless configured: Discord (both vars), Notion (both vars), S3 (all four vars), a GitHub token inside the sandbox, a cloud extract key, Exa, and voice keys. Discord also needs the operator to enable Message Content and Server Members intents before the gateway can see messages. The control plane does not do that portal step.

`PARALLEL_API_KEY` and `EXA_API_KEY` are forwarded if set. They are optional skill inputs, not control-plane features. This PRD does not define a product behavior for them beyond forwarding.

## 11. Data governance

- Classification: operator secrets and tenant ids are private. Skill bodies and cron jobs are private to the operator even though they are not secrets. Docs and the published contract are the public surface.
- Residency: runtime state stays on the agent host. The only off-host copy this product creates is the snapshot, and only of custom skills, the jobs file, and a manifest.
- Retention: this PRD sets none. Snapshot objects live until overwritten or deleted by the same writer. There is no lifecycle policy in the control plane.
- What must never enter git: `.env`, live tokens, tenant ids, skill bodies, the jobs file, profile seeds.
- What must never enter the sandbox: `AWS_*`, control-plane-only variables (FR-3).

## 12. Public surface

The published contract is three things:

- Make targets, as listed by `make help`. Adding, removing, or changing what an existing target does is a contract change.
- `.env.sample`, the list of variables an operator is expected to set, including which pairs are all-or-nothing.
- `config/config.yaml.example`, the behavior file. Model, terminal, web, and memory settings live here, not in env.

A contract change that makes an existing env file or Make invocation do the wrong thing is breaking (FR-22). The breaking-change trailer is the versioning policy. Semver tags are not required.

`extensions/registry.yaml` is not part of the published contract until something loads it (Open Question 6).

## 13. Risks

| Risk | Why it is real | What the product does today | Open |
|---|---|---|---|
| Allow-all copied if the operator sets it | Tests lock in copy-if-set. A stranger who copies a bad example would ship an open bot with a terminal. | Examples must not set it. The filter does not refuse `true`. | Question 1 |
| Public snapshot bucket | Skills and cron can contain personal workflow detail. The script does not check public access. | Operator must pre-create a private bucket. Documented, not enforced. | Question 4 |
| Skill, cron, and `ssh` can target the control-plane machine | Only deploy paths refuse localhost. | Documented hazard. Not enforced. | Question 5 |
| Author name strings in a public clone | Name strings are not secrets, but they are not the replicator's. Timezone and the model pin are published defaults on purpose. | Inherited on clone. | Question 3 |
| No license | Collaborators cannot tell what they may do with the tree. | `LICENSE` and `CONTRIBUTING` are absent. | Question 2 |
| Bare upstream update | Wipes the session-path patch and can break Telegram sandboxes. | Operator contract forbids it. The control plane cannot stop an SSH session that runs it anyway. | Accepted residual |
| `docker` group is root-equivalent | A sandbox escape or a widened forward list is host root. | Forward list is explicit. AWS keys excluded. | Accepted residual |
| CD runner holds prod secrets | A pipeline log or a committed env would publish the production bot. | Not built. FR-25 forbids secrets in git and in logs. | Accepted residual |
| Prod click offered too early | A sandbox click on a pull request must not be able to reach prod. | Not built. FR-25 refuses prod until merge to master. | Accepted residual |

## 14. Open questions

1. Should the filter refuse `GATEWAY_ALLOW_ALL_USERS=true` and `DISCORD_ALLOW_ALL_USERS=true`, or is the published-contract ban enough? Refusing protects a mistake. It also blocks an operator who set the flag on purpose, which upstream allows.
2. What license, and is a `CONTRIBUTING` guide in scope before the repo is shared? Both files are absent. "Safe to collaborate" is incomplete without them.
3. Before a public share, should author name strings in scripts and docs be generalized, or left as the author's defaults a replicator may ignore? Timezone and the model pin are decided: they stay.
4. Must snapshot refuse a bucket that is not private, or is the operator precondition enough? A check can false-fail when the key can write objects but cannot read the public-access block.
5. Should skill push, skill pull, cron push, cron pull, and interactive `ssh` refuse the control-plane machine the same way deploy does?
6. Is `extensions/registry.yaml` a requirement (scripts must load it) or documentation debt? Nothing reads it today.

## 15. Assumptions index

None. The ten draft assumptions were confirmed and are now decisions. The record is in `.memlog.md`.
