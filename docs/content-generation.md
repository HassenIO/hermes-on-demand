# Content generation (long-form)

Skills-first pipeline for newsletters, blog posts, business reports, and ebooks. Spec and research: `docs/tasks/large-content-generation.md`.

## Skills

| Skill | Path | Role |
|---|---|---|
| `editorial-os` | `skills/content/editorial-os/` | Shared pipeline, epistemics, voice, verify, model routing, publish |
| `newsletter` | `skills/content/newsletter/` | Digests / recurring newsletters |
| `blog-post` | `skills/content/blog-post/` | Single articles |
| `business-report` | `skills/content/business-report/` | Decision-oriented briefs |
| `ebook` | `skills/content/ebook/` | Multi-chapter, resumable |
| `ai-transformation-analyst` | `skills/research/ai-transformation-analyst/` | Specialist AI executive briefs (domain template) |

Always load **editorial-os** with a genre skill.

```text
/editorial-os /newsletter daily AI agents digest for senior engineers
/blog-post write a post on why outline-lock beats one-shot LLM drafts
/business-report short brief: should we adopt X in the next planning cycle?
/ebook start a short guide on Mnemosyne for personal agents (3 chapters)
```

Or: “Follow editorial-os and blog-post. Topic: …”

## Pipeline

Brief → Research → Outline → Draft → Verify → Publish

- Parallelize **research** (`delegate_task`).
- Single **writer** for final prose; ebook chapters sequential + continuity pass.
- Artifacts under `~/.hermes/content/<genre>/<slug>/`.

## Models

| Stage | Model |
|---|---|
| Research | Default (`xiaomi/mimo-v2.5` or current) OK |
| Draft + verify | **Stronger** — see `skills/content/editorial-os/references/model-routing.md` |

Cron content jobs should set `"model"` to the write model (Go newsletter is pinned).

## Deploy

```bash
make skills-push    # push skills/content to VPS
make push-artifacts # SOUL.md
make cron-push      # after editing cron/jobs.json
```

On VPS, new sessions pick up skills (`/new` or next cron fire).

## Cron pattern

- Attach skills: `editorial-os` + genre
- Self-contained prompt (no chat memory)
- Pin strong `model` for write quality
- Final response = user-visible deliverable for gateway `deliver`
- Long pieces: file + Notion; short digests may be full text in-channel

## Notion

Prefer `notion-page-authoring` for structured pages. Avoid paragraph-only `create-report` when headings matter.

## Docker / paths

Ensure the terminal sandbox can write `~/.hermes/content/` (add a volume in `config.yaml` if writes fail inside Docker). Read-only mounts will block file publish — fix mounts before relying on ebook state.
