---
title: 'Local unit tests for deploy regressions'
type: 'feature'
created: '2026-10-17'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: '377b802800647c74959a8f104991a970ef69a030'
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/COMMIT_GUIDELINES.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The rules that keep a bad edit off the VPS — secret filtering, localhost refusal, cron job shape, cron model pin, and config invariants — are inline in scripts that SSH before the check, or are comments. A regression is invisible until someone deploys.

**Approach:** Extract those pure decisions into functions the scripts already call, and cover them with local pytest. Document that `make test` is required when those decisions change. No SSH and no VPS.

## Boundaries & Constraints

**Always:** Tests call the same function the script calls. Do not reimplement a rule inside the test. Preserve current error text and current accept/reject behavior. `make test` is the entry point and must not SSH. `bash -n` still applies to edited shell scripts. Python stays 3.12-compatible. Update `AGENTS.md` and `COMMIT_GUIDELINES.md` so a later agent runs `make test` and does not claim there is no test runner.

**Never:** No deployment, health, or Telegram tests. No Docker, SSH, or network. No GitHub Actions. Do not add a unique-name check; the code does not enforce unique names. Do not test `notion_cli.py`. Do not change what `SKIP_*` does, and do not unit-test SSH modes. Do not commit `.env`, `skills/**`, `cron/**`, or `artifacts/**` except READMEs.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Local host refused | `TARGET_HOST` is `localhost`, `127.0.0.1`, or `::1`; `ALLOW_LOCAL_TARGET` unset | Guard fails | Non-zero, message names the host |
| Local override | Those hosts and `ALLOW_LOCAL_TARGET=1` | Guard allows | N/A |
| Other host | `TARGET_HOST=example.vps` | Guard allows | N/A |
| Runtime env defaults | Required Telegram and OpenRouter vars set; deploy-only vars also set in the environment | Output has the three required keys, `FIRECRAWL_API_URL=http://127.0.0.1:3002`, `SEARXNG_URL=http://127.0.0.1:8888`, `HERMES_TELEGRAM_DISABLE_FALLBACK_IPS=true`, `TIMEZONE` and `TZ` `Asia/Dubai`. Absent: `TARGET_*`, `SSH_*`, `REMOTE_DIR`, `ALLOW_LOCAL_TARGET`, `SKIP_*`, `PIN_CRON_FORCE`, `FIRECRAWL_MODE`, `LLM_MODEL` | N/A |
| Discord half pair | Only `DISCORD_BOT_TOKEN` or only `DISCORD_ALLOWED_USERS` | No `DISCORD_*` key in the output | N/A |
| Discord both | Both set | Both keys present; `DISCORD_ALLOW_ALL_USERS` present only if that var is set | N/A |
| Notion half pair | Only one of `NOTION_API_KEY` and `NOTION_REPORTS_PARENT_PAGE_ID` | No `NOTION_*` key | N/A |
| Notion both | Both set, `NOTION_TOKEN` unset | `NOTION_API_KEY`, `NOTION_REPORTS_PARENT_PAGE_ID`, and `NOTION_TOKEN` equal to the API key | N/A |
| AWS stays on the host env | `AWS_ACCESS_KEY_ID` set | Key is in the runtime env output. This is host env, not `docker_forward_env` | N/A |
| Allow-all unset | `GATEWAY_ALLOW_ALL_USERS` unset | Key absent. If set, the value is copied; the script does not force `false` | N/A |
| Cron reject | Empty list, missing id, duplicate id, missing name, or `schedule` not an object | `cron-push` validator rejects | Existing error text |
| Cron accept | One job with unique string id, name, and schedule object | Validator accepts. A second job with the same name and a different id is accepted | N/A |
| Pin skip | Job `model` set and different from `model.default`; force off | Classified skip | N/A |
| Pin default | Model empty or equal to `model.default` | Classified pin | N/A |
| Pin force | `PIN_CRON_FORCE` in `1`, `true`, `yes` | Every job classified pin | N/A |
| Config invariants | `config/config.yaml.example` | `memory_enabled` and `user_profile_enabled` are false; `docker_forward_env` has no `AWS_*`; web search is searxng and extract is firecrawl; `model.default` is set; no `LLM_MODEL`; no secret-looking values | N/A |
| Gitignore | A file under `skills/`, `cron/`, or `artifacts/` that is not `README.md`, and `.env` | `git check-ignore` matches. `README.md` in those trees is not ignored | N/A |
| Makefile contract | `Makefile` | Every target is `.PHONY` and has a `##` comment. Only `deploy` and `full` invoke `deploy.sh` with no mode flag | N/A |
| Skill unpack | Temp archive with a custom skill, a `README.md`, and a path that exists under a fake builtin dir; `--prune` and a pre-existing extra package | README not installed; builtin path refused; extra package removed | Non-zero on builtin collision |

</frozen-after-approval>

## Code Map

- `scripts/deploy.sh` lines 48–52 and 83–141 — localhost guard and `RUNTIME_ENV` block. Extract both. Do not move them after the SSH probe, and do not change the SSH probe. The filter today runs after SSH; the extracted function must be callable without SSH, and `deploy.sh` may call it at the same point it does now.
- `scripts/lib/common.sh` `load_dotenv` and `require_vars` — source and call. Do not rewrite.
- `scripts/cron-push.sh` lines 36–59 — local validator, before SSH. Extract this check only. Keep its error strings.
- `scripts/remote/install-cron-jobs.sh` lines 42–80 — VPS validator then `cron.jobs.save_jobs`. Do not import Hermes in tests. Leave this script's Hermes import alone unless the shared validator can be called before that import without changing accept/reject results.
- `scripts/remote/pin-cron-models.sh` lines 77–101 — pin/skip classification. Extract the decision. The shell may still skip when `hermes` or `config.yaml` is missing; do not require `hermes` in the unit test.
- `scripts/remote/unpack-custom-skills.sh` — already runnable with `HERMES_HOME` and `HERMES_BUILTIN_SKILLS`. Run it in a temp dir. Do not change prune or builtin rules.
- `config/config.yaml.example`, `.gitignore`, `Makefile` — assert. Do not edit them except a new `test` target on the Makefile.
- `AGENTS.md` "Running and verifying" — today says there is no test runner. Replace that claim.
- `COMMIT_GUIDELINES.md` — today forbids `test:`. Allow it for test-only commits, and require `make test` before committing a behavior change.
- `pack-custom-skills.sh` `should_include` and `s3-snapshot.sh` `should_include` — same README/dotfile rule, copied. Do not merge them in this change.

## Tasks & Acceptance

**Execution:**
- [x] `scripts/lib/runtime-env.sh` -- add `refuse_local_target` and `build_runtime_env` with the current rules -- so pytest and `deploy.sh` share one filter
- [x] `scripts/deploy.sh` -- call those functions; leave SSH, modes, and chmod 600 as they are -- no deploy behavior change
- [x] `scripts/lib/cron_validate.py` -- move the `cron-push.sh` pre-SSH checks here, same error strings -- local reject/accept without a network
- [x] `scripts/cron-push.sh` -- call that module before SSH -- the script no longer inlines the check
- [x] `scripts/lib/pin_decision.py` -- move the pin/skip classification here -- force, empty, equal, and different stay the same
- [x] `scripts/remote/pin-cron-models.sh` -- call that module for the classification -- `hermes` still required only for the edit step
- [x] `pyproject.toml` -- pytest as a dev dependency, Python `>=3.12` -- `make test` has a runner
- [x] `tests/` -- one module per matrix group, calling the extracted functions or `unpack-custom-skills.sh` in tmp -- no second copy of the rules
- [x] `Makefile` -- `test` target with `##` and `.PHONY`, runs pytest, no `.env` and no SSH -- matches the other entry points
- [x] `docs/11-testing.md` -- philosophy: local decisions only, `make test` before a feature that touches those functions, do not add VPS tests here -- agents have a page to read
- [x] `README.md` and `docs/00-overview.md` -- link that page -- the index does not drift
- [x] `AGENTS.md` and `COMMIT_GUIDELINES.md` -- `make test` is required; there is a test runner; `test:` is allowed for test-only commits; do not weaken or skip these tests to land a feature -- the loaded instruction matches the suite

**Acceptance Criteria:**
- Given a clean tree and no network, when `make test` runs, then every matrix row passes and no test opens a socket or invokes `ssh`.
- Given `AGENTS.md`, when an agent is about to change `deploy.sh`, cron validation, or the pin decision, then the loaded instruction tells it to run `make test` and to extend the suite if the decision changes.
- Given `COMMIT_GUIDELINES.md`, when the change is tests only, then `test:` is the type; when the change is a script behavior change, then `make test` is part of the pre-commit check alongside `bash -n`.

## Implementation Notes

- Extracted `refuse_local_target` and `build_runtime_env` into `scripts/lib/runtime-env.sh`. `deploy.sh` still refuses localhost before the SSH probe and still builds the runtime env after it. `chmod 600` is unchanged. The function ends with `return 0` so a trailing conditional echo does not abort under `set -e`.
- `cron-push.sh` calls `scripts/lib/cron_validate.py` before SSH. `install-cron-jobs.sh` kept its own validator and Hermes import.
- `pin-cron-models.sh` calls `scripts/lib/pin_decision.py`. `hermes` is still required only for the edit step.
- `make test` ran 46 passed. `bash -n` was reported clean on the edited shell scripts.

## Spec Change Log

## Review Triage Log

- false — cron CLI exits 0 on a bad file. `python3 scripts/lib/cron_validate.py` on a duplicate id exits 1 and prints `duplicate id: a` on stderr. `main()` does not catch `SystemExit`.
- false — pin CLI ignores force. `pin_decision.py` with force `1` prints `pin`, force `0` prints `skip` for an override model. `main()` passes `is_force(argv[3])` into `decision_line`.
- defer — local cron gate still accepts a non-string id and a whitespace name that `install-cron-jobs.sh` rejects. That split existed before the extract. The spec said keep the pre-SSH strings and leave the VPS validator alone.
- defer — `build_runtime_env` writes raw `KEY=value`, so a metacharacter in a value can break a later `source`. The old inline block did the same. Not introduced here.
- defer — pin TSV can split if an id or name contains a tab. The old inline printer used the same format.
- defer — `unpack-custom-skills.sh` resolves skill roots but not `tempfile.mkdtemp()`, so a symlinked `TMPDIR` can fail `relative_to`. The script was not to be changed. The test sets a real `TMPDIR` so macOS can run it.
- low, rejected — runtime-env tests lock defaults, not every optional forward. The approved matrix asked for defaults, half pairs, and AWS presence. Those ran and passed.
- low, rejected — Makefile test does not imagine a future `full: health` recipe. Current `full` is an alias of `deploy`, and the suite passed against that file.
- low, rejected — `make test` does not also prove the interpreter is 3.12. The suite ran and passed on the interpreter that has pytest.
- low, rejected — config scan is not a YAML parser. It locks the keys the matrix named in the current example file, and that test passed.
- low, rejected — `Localhost` is not refused. The matrix names `localhost`, `127.0.0.1`, and `::1`. Those three failed closed in the run.
- low, rejected — the ssh/socket stubs do not cover every child binary. No test invoked `ssh` or opened a Python socket. `make test` printed 46 passed.
- low, patched — `docs/11-testing.md` headed a column "Called from" and listed the defining file. Renamed it to "Defined in" and added the caller.

## Design Notes

Keep one implementation. A test that restates the filter in Python will pass after the bash filter drifts. `pytest` may subprocess a bash function or import a module the script calls. It must not own a second copy of the rule.

`install-cron-jobs.sh` may keep its own loop if sharing the module would pull in `cron.jobs` or change an error string. The local gate that runs before SSH is the one this suite owns.

`load_dotenv` / `require_vars` are already functions. Cover quoted values, comments, and a missing required var by sourcing `common.sh` in a subprocess. Do not add that coverage by rewriting `common.sh`.

## Verification

**Commands:**
- `make test` -- expected: all tests pass, no SSH, exit 0
- `bash -n` on each edited shell script -- expected: exit 0
