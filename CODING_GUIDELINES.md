# Coding guidelines

`master` is the integration branch. Do not commit on it. Do not push to it. Every change is a branch and a pull request into `master`.

This repo has no `develop` branch. Do not create one. Feature and bugfix branches start from current `origin/master` and merge back only through a pull request.

Commit message format stays in `COMMIT_GUIDELINES.md`. This file is the branch and pull-request procedure.

## Before editing

```bash
git fetch origin
git checkout master
git pull --ff-only origin master
git checkout -b <prefix>/<kebab-summary>
```

If `git pull --ff-only` fails, stop. Do not merge, rebase, or reset `master` to get past it. Say what the remote did.

Confirm `git branch --show-current` is not `master` before the first edit. If it is `master`, create the branch before writing files.

## Branch names

Gitflow prefixes. `<kebab-summary>` is a few lowercase words with hyphens. No spaces. No ticket number unless the user gave one.

| Change | Prefix | Example |
|--------|--------|---------|
| New behavior, docs, tests, or chore (`feat`, `docs`, `test`, `refactor`, `chore`) | `feature/` | `feature/local-unit-tests` |
| A wrong behavior (`fix`) | `bugfix/` | `bugfix/skipped-notion-log` |
| Urgent repair of what is already on `origin/master` | `hotfix/` | `hotfix/colon-path-patch` |
| A versioned release cut the user asked for | `release/` | `release/1.2.0` |

Do not invent `docs/`, `chore/`, or `test/` prefixes. Those changes still use `feature/`.

Do not use `hotfix/` for ordinary work. It is only for a repair that must land while other feature branches stay open.

## Commits

Commits go on the feature branch, never on `master`.

Still follow `COMMIT_GUIDELINES.md`: `<type>[(<scope>)]: <subject>`, imperative, sentence case, no trailing period, subject at most 50 characters, body says why.

Do not commit unless the user asked. Do not push unless the user asked. When they ask to commit, commit on the current feature branch. When they ask to submit, push that branch and open the pull request. Do not treat "commit" as permission to push or to merge.

## Pull requests

- One branch, one pull request, base `master`.
- Title matches a commit subject: `<type>[(<scope>)]: <subject>`. It may run past 50 characters if a shorter title would be unclear.
- Body says why, and how to test. For a script change that is `bash -n` on the edited scripts. For a behavior change after `make test` exists on the branch, include that too.
- Do not merge the pull request unless the user asked.
- Do not force-push `master`. Force-push a feature branch only if the user asked to rewrite that branch.

```bash
git push -u origin HEAD
gh pr create --base master --title "<type>: <subject>" --body "<why>"
```

## If a commit landed on master by mistake

Check first:

```bash
git fetch origin
git branch --contains HEAD
git status -sb
```

If that commit is not on `origin/master`:

```bash
git branch feature/<kebab-summary>
git checkout master
git reset --hard origin/master
```

The commit stays on the new branch. `master` matches the remote. Then push the feature branch and open a pull request. Do not push `master`.

If the commit is already on `origin/master`, do not reset and do not force-push. Stop and tell the user.

## Never

- Commit, merge, or push directly to `master`.
- Start work on `master` and move it later if you can branch first.
- Create `develop`.
- Put secrets, or runtime copies under `skills/`, `cron/`, or `artifacts/` except each `README.md`, in a commit or a pull request.
