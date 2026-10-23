# Version and technology review — Hermes architecture spine

Reviewer: version/reality-check pass
Date: 2026-10-19
Artifact: `_bmad-output/planning-artifacts/architecture/architecture-Hermes-2026-10-18/ARCHITECTURE-SPINE.md`
Verdict: **fix**

The stack table labels the action pins as tree pins, and those pins still execute. It does not record two currency facts a CD story would copy: both pins are Node 20 actions GitHub is already force-running on Node 24, and `astral-sh/setup-uv` has moved five majors past the pin. `ubuntu-latest` is also inside a published OS migration that started today. Those three rows need a dated note before the spine is a safe build substrate. Nothing else named in the stack was found missing or mis-fit.

## Method

Checked the spine stack and the version-shaped claims it depends on against the tree, a green Actions run, and the web on 2026-10-19. Treated as already checked, and not re-litigated: public-repo Environment secrets, required reviewers, and deployment branch rules; `actions/checkout` v7.0.1 as the latest found on 2026-07-20; Ubuntu 22.04 and 24.04 as the documented agent-host choices; the model id as a tree pin.

Sources used this pass:

- Tree: `.github/workflows/pr-checks.yml`, `pyproject.toml`, `config/config.yaml.example`, `docs/00-overview.md`, `docs/01-prerequisites.md`, `docs/11-testing.md`, `firecrawl/docker-compose.yml`, `scripts/remote/bootstrap.sh`, `scripts/remote/s3-snapshot.sh`
- Actions run `39150352372` on `HassenIO/hermes-on-demand`, success, 2026-10-18T17:36:15Z
- https://github.com/astral-sh/setup-uv/releases (latest v10.3.0, published 2026-10-09)
- https://api.github.com/repos/astral-sh/setup-uv/git/ref/tags/v5 (tag exists)
- `action.yml` at `actions/checkout@v4` (`runs.using: node20`), `actions/checkout@v5.0.0` (`node24`), `astral-sh/setup-uv@v5` and `@v6.0.0` (`node20`), `@v10.3.0` (`node24`)
- https://github.blog/changelog/2025-09-19-deprecation-of-node-20-on-github-actions-runners (editor note 2026-08-25: Node 20 removed 2026-09-23)
- https://github.blog/changelog/2026-09-17-ubuntu-26-generally-available-and-latest-migration
- https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments (deployment branch rule matches `GITHUB_REF`; prevent-self-review exists)
- https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax (`workflow_dispatch` only receives events when the file is on the default branch; `GITHUB_REF` is the branch or tag that received dispatch)
- https://hermes-agent.nousresearch.com/install.sh (`--skip-browser` still accepted)
- https://docs.astral.sh/uv/reference/cli/ (`uv run --no-env-file` still documented) and https://docs.astral.sh/uv/reference/environment/ (`UV_NO_ENV_FILE`)
- https://openrouter.ai/xiaomi/mimo-v2.5 (model page still documents the id)
- https://github.com/firecrawl/firecrawl/pkgs/container/firecrawl (`ghcr.io/firecrawl/firecrawl:latest` published the same day)

## Findings

### 1. Medium — action pins are tree pins, but the "do not bump" line hides a Node 20 force-run

The stack intro is right that these are not a bump, and right that checkout v7.0.1 existed as of 2026-07-20. It is incomplete as of this review.

Both pins declare `runs.using: node20`:

- `actions/checkout@v4`
- `astral-sh/setup-uv@v5`

GitHub's changelog says Node 20 was removed from runners on 2026-09-23. It has not stopped these pins yet. Run `39150352372` (2026-10-18) succeeded and logged:

> Node.js 20 is deprecated. The following actions target Node.js 20 but are being forced to run on Node.js 24: actions/checkout@v4, astral-sh/setup-uv@v5.

`actions/checkout@v5.0.0` and `astral-sh/setup-uv@v10.3.0` declare `node24`. The spine's "A CD story does not bump it" is safe only as "do not bump inside the CD change." It is not safe as "copy these pins, they are current." A deploy workflow that copies the table would copy actions GitHub is already warning about. They still run under the force-compat layer. That layer is not a published promise.

Required edit: in the stack intro, record the 2026-10-18 warning and the force-run. Keep the pins. Say a CD story copies them and does not bump them unless that force-run has stopped succeeding. A bump is a separate change.

### 2. Medium — `astral-sh/setup-uv` v5 is a real tag, and it is not current

Verified before accepting the row:

- Tag `v5` still exists (`e58605a9b6da7c637471fab8847a5e5a6b8df081`).
- Latest release is **v10.3.0**, published 2026-10-09T20:41:00Z. It uses `node24`.
- v6.0.0 still used `node20`. The node24 move is not the v5-to-v6 jump.
- v9 changed the `prune-cache` default to `false`. v10 disables automatic cache on `pull_request_target`, `workflow_run`, and `release` when `enable-cache` is `auto`. The tree sets `enable-cache: true` explicitly in `pr-checks.yml`, so a later bump is not a drop-in.

The row says "v5, as pinned in pr-checks.yml" under "Tree pins, not a bump." That labels it as a tree pin, not as current. Unlike checkout, it does not record that a newer major exists. A reader of the intro could think only checkout is behind.

Required edit: same shape as the checkout sentence. v5 is the tree pin. v10.3.0 exists as of 2026-10-09. A CD story does not bump it.

### 3. Low — `ubuntu-latest` is a floating label inside a migration that started today

The row names the label. It does not claim an Ubuntu version, and it matches `pr-checks.yml`. The label still exists.

GitHub's 2026-09-17 changelog: `ubuntu-latest` migrates from Ubuntu 24.04 to 26.04 gradually between 2026-10-19 and 2026-11-19. Today is the first day of that window. The same job can land on either image until 2026-11-19. GitHub says the move may break workflows that depend on image-provided tools, and that `ubuntu-24.04` is the pin if you are not ready.

The CD runner only needs bash, ssh, scp, and make, then SSHes to an Ubuntu 22.04 or 24.04 agent host. That is a weaker dependency than a build that uses image-preinstalled compilers. Still, the stack row presents the label as a settled choice and does not record the window.

Required edit: one sentence on the runner row. `ubuntu-latest` is the same label as pull-request checks. As of 2026-10-19 it is migrating from 24.04 to 26.04 through 2026-11-19. It is not an OS pin. A CD story does not switch it to `ubuntu-24.04` unless a check fails on 26.04.

## Accepted

| Name | Spine claim | Check | Result |
| --- | --- | --- | --- |
| Agent host OS | Ubuntu 22.04 or 24.04 | `docs/00-overview.md`, `docs/01-prerequisites.md` | Tree choice, not claimed as the only current Ubuntu. Accepted. |
| actions/checkout | v4, as pinned | `pr-checks.yml` line 21; v4 tag still resolves | Tree pin. Newer release note is present, but see finding 1. |
| Python for unit tests | `>=3.12`, from `pyproject.toml` | `pyproject.toml` `requires-python`. Run `39150352372` cache key used 3.12.3 | Matches the tree. Not claimed as the runner default. |
| Upstream Hermes Agent | not vendored; official installer, `--skip-browser` | Live `install.sh` still accepts `--skip-browser` (alias `--no-playwright`). `bootstrap.sh` still curls that URL with the flag | Flag still exists. Spine does not pin a Hermes version. Accepted. |
| Model pin | `xiaomi/mimo-v2.5` in `config/config.yaml.example` | Tree line 11. OpenRouter model page still documents the id | Accepted. Not a live completion call. |
| Provider | OpenRouter | Same page | Still the catalog host for that id. |
| Process manager | systemd user service, linger | Documented agent-host choice in `docs/00-overview.md` | Not a version. Still the published host choice. Not re-fetched from systemd docs. |
| Firecrawl compose images | floating tags already in `firecrawl/docker-compose.yml`; not newly pinned | Compose still has `:latest` / `:alpine` / local `hermes-firecrawl-lite:local`. `ghcr.io/firecrawl/firecrawl:latest` published the same day (2.11.542) | Correctly not claimed as pins. Other image names in that file were not individually resolved. |
| `uv run --no-env-file pytest` | AD-15 published contract | Current uv CLI docs still list `--no-env-file`. `docs/11-testing.md` requires it | Flag still exists. |
| GitHub Environments `prod` / `sandbox`, deployment branches `master` | AD-4 | Current docs: selected-branch rules match `GITHUB_REF`, not a later checkout SHA. Available on public repos | Fits. Checking out a pull-request SHA does not change the ref the rule sees. The master workflow must still attest the SHA, as AD-5 says. |
| `workflow_dispatch` of the workflow file on `master` | AD-5 | Current syntax docs: the event only fires if the workflow file is on the default branch. `GITHUB_REF` is the branch or tag that received the dispatch | Fits this repo's `master` default. A write user can still dispatch another ref if the file also exists on the default branch. The environment rule, not the workflow file, is the gate. That matches AD-4. |
| No required reviewer, do not enable prevent-self-review | AD-4 | Both settings still exist in current environment docs. A waiting review job still fails after 30 days | The refusal is a product choice, not a missing feature. |
| Per-workflow actor allowlist | Deferred, "not confirmed available" | Not found in the environment or workflow-syntax pages read this pass | Uncertainty label is the right posture. Do not add one. |
| Concurrency groups, `cancel-in-progress: false` | AD-17 | Same syntax already used in `pr-checks.yml` (`cancel-in-progress: true` there) | Feature exists and fits. |
| Snapshot AES256 | AD-14 | Tree flag `--sse AES256` in `scripts/remote/s3-snapshot.sh` | Tree flag, not a new pin. AWS docs not re-fetched this pass. |
| `pull_request` / `pull_request_target` / `workflow_run` deploy forbidden | AD-5 | Changelog 2026-09-17: public repos on the default policy block `pull_request_target` from 2026-11-02. That date is in `CD-DISCUSSION.md`, not the spine | Spine decision does not depend on the date. The date in the discussion is still what GitHub published. |

## Not a defect

- Checkout v7.0.1 "as of 2026-07-20" was given as already checked. This pass did not look for a checkout release after that date. Finding 1 is about the pin's runtime, not about whether v7.0.1 is still the newest tag.
- The live installer now defaults the official repo to the `stable` channel and remembers `--skip-browser` for later `hermes update`. The spine does not claim a channel or a Hermes version. No stack edit.
- Firecrawl `playwright-service`, `nuq-postgres`, SearXNG, Redis, and RabbitMQ tags were not resolved one by one. The spine already refuses to newly pin them.

## Required spine edit

One paragraph and two table cells in `## Stack`. Do not bump any pin in that edit.

1. After the checkout sentence, add that both `actions/checkout@v4` and `astral-sh/setup-uv@v5` declare `node20`, that run `39150352372` on 2026-10-18 succeeded while GitHub forced them onto Node 24, and that a CD story copies the pins and does not bump them unless that force-run has stopped.
2. On the setup-uv row, record that v5 is the tree pin and that v10.3.0 (2026-10-09) exists and uses `node24`.
3. On the runner row, record that `ubuntu-latest` is migrating from 24.04 to 26.04 between 2026-10-19 and 2026-11-19, and that a CD story does not pin `ubuntu-24.04` unless a check fails on 26.04.
