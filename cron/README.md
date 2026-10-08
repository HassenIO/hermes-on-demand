# cron

Local copy of Hermes scheduled jobs. `jobs.json` is not committed. This README is the only Git file in this folder.

`jobs.json` is the job set. Pull before editing, then push:

```bash
make cron-pull
# edit cron/jobs.json
make cron-push
```

`cron-push` replaces the remote set. On the VPS the file lives at `~/.hermes/cron/jobs.json`. The S3 watcher mirrors that file after a change. Do not put tokens in `jobs.json`.
