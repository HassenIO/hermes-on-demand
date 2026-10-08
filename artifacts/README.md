# artifacts

Profile seeds for the VPS. These files are not committed. This README is the only Git file in this folder.

| File | Installed to | Role |
|------|----------------|------|
| `SOUL.md` | `~/.hermes/SOUL.md` | Agent identity |
| `USER.md` | `~/.hermes/memories/USER.md` | User profile. Entries separated by a line containing only `§` |
| `MEMORY.md` | `~/.hermes/memories/MEMORY.md` | Agent notes. Same `§` format |
| `CV.md` | `~/.hermes/CV.md` | Full CV. Read on demand, not injected every turn |

Edit the files here, then push:

```bash
make push-artifacts
```

In Telegram, send `/new` so the next session reloads them. Mnemosyne is the runtime memory store. These files are seeds and rollback copies, not the S3 snapshot.
