# artifacts

Profile seeds for the VPS. These files are not committed. This README is the only Git file in this folder.

| File | Installed to | Role |
|------|----------------|------|
| `SOUL.md` | `~/.hermes/SOUL.md` | Agent identity |
| `USER.md` | `~/.hermes/memories/USER.md` | User profile. Entries separated by a line containing only `§` |
| `MEMORY.md` | `~/.hermes/memories/MEMORY.md` | Agent notes. Same `§` format |
| `CV.md` | `~/.hermes/CV.md` | Full CV. Read on demand, not injected every turn |

Edit the files here, then sync:

```bash
make sync
```

Hermes edits `USER.md` and `MEMORY.md` at runtime, so `make push-artifacts` would overwrite those edits.
`make sync` works like a git merge instead.
It compares each file with the copy from the last sync in `.hermes-setup/artifacts/` (gitignored).
Remote-only changes are pulled here, local-only changes are pushed, and changes on both sides are merged with `git merge-file`.
On a conflict, the file here gets git conflict markers and nothing is pushed.
Fix the markers, then run `make sync` again.
The first run seeds `.hermes-setup/artifacts/` from the last push on the VPS (`~/hermes-setup/artifacts/`).

In Telegram, send `/new` so the next session reloads them. Mnemosyne is the runtime memory store. These files are seeds and rollback copies, not the S3 snapshot.
