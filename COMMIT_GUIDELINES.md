# Commit guidelines

Rules for commit messages in this repo. This is infrastructure-as-code for a Hermes VPS. The product is the deploy scripts, config, and docs. A script or doc fix is a real fix.

There is no commit-msg hook and no pull-request template file. Pull requests are still required. Branch, review, and pull-request steps are in `CODING_GUIDELINES.md`. Do not commit on `master`. Do not commit or push until the user has reviewed the work and explicitly said to. `make lint` and `make test` are the local checks. Pull requests run both in `.github/workflows/pr-checks.yml`. Agents follow both files.

## Format

```
<type>[(<scope>)]: <subject>

<body>
```

### Subject

- Required.
- `<type>: <subject>` or `<type>(<scope>): <subject>`.
- Imperative, sentence case: `Add a deploy test`, not `Added a deploy test`.
- No trailing period.
- At most 50 characters, including the type and scope.
- Say what changed. `fix: Correct deploy log` is not enough. Name the behavior.

### Scope

Optional. One lowercase word, no spaces. Use it when the subject does not already name the area.

`deploy`, `config`, `docs`, `skills`, `cron`, `gateway`, `notion`, `firecrawl`, `s3`, `artifacts`, `security`.

Omit it for a cross-cutting change, or when the subject is already specific.

### Body

Required when the subject cannot carry the why. Explain why the change exists, not which files moved. Git already lists the files.

Wrap at 72 characters. Separate paragraphs with a blank line. Use bullets only for a few related effects.

Do not write `Address review feedback` or `Fix Copilot comments`. Name the actual problem.

### Footer

Optional. Use only what the user gave you.

- `Resolves #123` when they named an issue. Do not invent an issue number. This repo has no issue tracker wired in.
- `BREAKING CHANGE:` when a Makefile target, deploy flag, or env contract changes and an existing `.env` or script call would do the wrong thing.
- Do not add `Co-Authored-By`, `Generated with`, or any other AI attribution unless the user asked.

## Types

| Type | Use here |
|------|----------|
| `feat` | A new deploy path, extension, script behavior, or config contract |
| `fix` | A wrong script, Makefile, config, or doc that would make a deploy or an agent do the wrong thing |
| `docs` | Documentation only, including a docs link |
| `refactor` | Restructure scripts without changing what deploy does |
| `chore` | Maintenance that is not a behavior change (ignore rules, wording that does not correct a lie) |
| `test` | Tests only. No script, config, or behavior change |
| `revert` | Revert an earlier commit |

`test:` is for a commit that only adds or edits tests. A script or config behavior change uses `feat`, `fix`, or `refactor`, not `test:`.

`ci:` is only for `.github/workflows`. A script or config behavior change is not `ci:`.

`perf:` and `style:` are rare. A new Makefile target is `feat`, not `build`. A help line that described a target wrongly is `fix`.

## What never goes in a commit

- Secrets, tokens, or Notion/Discord IDs. Placeholders stay in `.env.sample`.
- `skills/**`, `cron/**`, and `artifacts/**`, except each tree's `README.md`.
- A half-finished change. Do not use `wip:`. There is no squash-merge step that will clean it up.
- Unrelated edits in the same commit.

## Examples

```
docs: Add a disposable-VPS deploy test

Operators were re-running make deploy against the live bot to see if
a change worked. Describe a throwaway host, a separate BotFather
token, and which health warnings still mean the default stack failed.
```

```
fix(deploy): Correct the skipped-Notion log

The log said no VPS changes were made after payload sync and timezone
had already run. Say what actually ran so the next agent does not
treat setup-notion as a no-op.
```

```
feat(s3): Mirror custom skills and cron jobs

One-way snapshot of those two paths only. The bucket must already
exist. SQLite, sessions, and secrets stay off the mirror.
```

```
test: Cover cron shape rejects

A bad jobs.json used to fail only after upload. Lock the
pre-SSH error strings so a later edit cannot drift them.
```

## Before committing

1. The user reviewed the summary and test steps, and explicitly said to commit. `git branch --show-current` is not `master`. If it is `master`, follow `CODING_GUIDELINES.md` before committing.
2. The subject matches a type above and is within 50 characters.
3. The body says why, if the subject does not.
4. `make lint` and `make test` passed. After `make install-hooks`, the pre-commit hook runs both and refuses the commit if either fails. Do not use `git commit --no-verify` to skip that gate. Do not weaken or skip tests to make a commit pass.
5. The diff has no secrets and no runtime copies under `skills/`, `cron/`, or `artifacts/`.
