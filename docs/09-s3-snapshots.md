# S3 snapshots (skills + cron)

One-way mirror of **custom skills** and **cron jobs** from the VPS to AWS S3. After the watcher is installed, edits on the VPS upload themselves. This is not `rsync`, and it is not a live filesystem mount.

SQLite (Mnemosyne), chat sessions, logs, Docker volumes, and secrets are **not** uploaded.

## What is synced

| VPS path | S3 object | Notes |
|----------|-----------|--------|
| Custom packages under `~/.hermes/skills/` | `<prefix>/skills/` | Same filter as `scripts/remote/pack-custom-skills.sh`: skip Hermes builtins, dotfiles, and `*.sha256` |
| `~/.hermes/cron/jobs.json` | `<prefix>/cron/jobs.json` | Single file. `jobs.json.bak.*` is ignored |
| (generated) | `<prefix>/manifest.json` | UTC time, hostname, skill counts, sha256 of `jobs.json`. No credentials |

Default prefix is `hermes/snapshot`, so the mirror is `s3://<bucket>/hermes/snapshot/`.

An empty custom-skill tree does **not** delete the remote `skills/` prefix. A missing `jobs.json` does **not** delete the remote job file. When custom skills exist, `aws s3 sync --delete` makes `<prefix>/skills/` match the stage.

## What is not synced

- `~/.hermes/mnemosyne/` and any other SQLite
- Session transcripts
- `~/.hermes/.env`, local `.env`, bot tokens, API keys
- Builtin skills under the Hermes install tree
- Firecrawl / SearXNG data

AWS keys are forwarded in the deploy payload (`remote.env`) so the VPS can upload. They are not listed in `terminal.docker_forward_env`, so the agent sandbox does not receive them. Do not put key values in git, docs, or `manifest.json`.

## Setup

1. Create a private S3 bucket. Block public access. The script does not create the bucket.
2. IAM on that key, scoped to the prefix:
   - `s3:ListBucket` on the bucket
   - `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` on `<prefix>/*`
3. In the local `.env` (never commit it), set:

| Variable | Required | Role |
|----------|----------|------|
| `AWS_ACCESS_KEY_ID` | yes | Upload identity |
| `AWS_SECRET_ACCESS_KEY` | yes | Upload secret |
| `AWS_DEFAULT_REGION` | yes | Bucket region |
| `S3_BUCKET` | yes | Bucket name |
| `S3_PREFIX` | no | Default `hermes/snapshot`. Rejects empty and `..` |

4. From the local machine:

```bash
make s3-snapshot
```

That SSHs to `TARGET_HOST`, installs `awscli` if missing, uploads once, installs `inotify-tools` if missing, and starts `hermes-s3-sync.service`. Full `make deploy` does the same when all four required variables are set. `make skills-push` and `make cron-push` refresh the snapshot and ensure the watcher is running when `S3_BUCKET` is set.

The gateway is not restarted.

## Watcher

`hermes-s3-sync.service` runs `scripts/remote/s3-sync-watch.sh`.

- Watches `~/.hermes/skills` (recursive) and `~/.hermes/cron/jobs.json`
- Ignores `jobs.json.bak*`, `*.sha256`, and dotfiles
- Waits `S3_SYNC_DEBOUNCE_SEC` seconds (default 10) after the last change, then runs `scripts/remote/s3-snapshot.sh`
- One snapshot at a time (`flock` on `~/.hermes/cache/s3-snapshot.lock`, 600s timeout)
- Restarts on failure (`Restart=on-failure`)
- Prefers a user systemd unit (linger, same idea as the gateway). If the user bus is not available over SSH, it installs a system unit that runs as `TARGET_USER`

Check it on the VPS:

```bash
systemctl --user status hermes-s3-sync.service
# or, if the installer fell back to a system unit:
systemctl status hermes-s3-sync.service
journalctl --user -u hermes-s3-sync.service -n 50
```

Uploads use `--sse AES256`. A VPS `AWS_PROFILE` is unset for the snapshot process so a machine profile cannot override the deployed key.

## Layout on the VPS

| Path | Role |
|------|------|
| `scripts/remote/s3-snapshot.sh` | Stage + `aws s3 sync` / `aws s3 cp` |
| `scripts/remote/s3-sync-watch.sh` | `inotifywait` loop |
| `scripts/remote/s3-sync-install.sh` | Enable or stop the unit |
| `~/hermes-setup/remote.env` | Credentials read at upload time (chmod 600) |

Incomplete AWS/S3 env stops the unit instead of leaving it crash-looping.

## Limits

- One writer. Do not run two gateways or two watchers against the same prefix.
- This does not restore a new VPS. It only pushes. Memory stays on the current disk.
- Local `make skills-push` / `make cron-push` overwrite the VPS, and the watcher then publishes that overwrite. A stale local copy can still replace S3.
- Not a continuous byte-level sync. A burst of writes becomes one upload after the debounce.
