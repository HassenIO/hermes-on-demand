# Content generation (long-form)

Skills-first pipeline for newsletters, blog posts, business reports, ebooks, tutorials, and courses. Spec and research: `docs/tasks/large-content-generation.md`.

## Skills

| Skill | Path | Role |
|---|---|---|
| `editorial-os` | `skills/content/editorial-os/` | Shared pipeline, epistemics, voice, verify, model routing, publish |
| `newsletter` | `skills/content/newsletter/` | Digests / recurring newsletters |
| `blog-post` | `skills/content/blog-post/` | Single articles |
| `business-report` | `skills/content/business-report/` | Decision-oriented briefs |
| `ebook` | `skills/content/ebook/` | Multi-chapter long prose, resumable |
| `tutorial` | `skills/content/tutorial/` | Single lesson + images, resources, fresh research |
| `course` | `skills/content/course/` | Intro + chapters + conclusion; mind map; images; resources; fresh research |
| `ai-transformation-analyst` | `skills/research/ai-transformation-analyst/` | Specialist AI executive briefs (domain template) |

Always load **editorial-os** with a genre skill.

```text
/editorial-os /newsletter daily AI agents digest for senior engineers
/blog-post write a post on why outline-lock beats one-shot LLM drafts
/business-report short brief: should we adopt X in the next planning cycle?
/ebook start a short guide on Mnemosyne for personal agents (3 chapters)
/tutorial teach Docker compose first deploy for backend beginners
/course build a 6-chapter course on prompt evaluation for ML engineers
```

### Tutorials vs courses vs ebooks

| | Tutorial | Course | Ebook |
|---|---|---|---|
| Hierarchy | sections → subsections | **intro + chapters + conclusion**; sections → subsections in chapters | chapters (prose) |
| Goal | Learn by doing one path | Curriculum + outcomes over time | Read/understand long form |
| Pedagogy | Diátaxis + Gagné | Outcomes matrix + Merrill + Gagné | Editorial narrative |
| **Visuals** | Destination + per section; prefer **web downloads** into `assets/` | Intro **mind map** + per chapter figures; prefer web downloads | Optional |
| **Resources** | Inline deep links + end **Resources used** | Same per chapter + conclusion full index | Sources as genre requires |
| **Freshness** | Live web search; pin versions/models as-of opened pages | Same | Same when technical |

Visual rules: `skills/content/editorial-os/references/instructional-visuals.md`.  
Freshness: `skills/content/editorial-os/references/freshness.md`.

**Source priority for images:** (1) **Download** from opened docs into `assets/`, (2) **`image_generate`** + save locally, (3) **Mermaid** only if both fail. Mermaid-only fails verify if downloads were possible. Attribute third-party images in `assets/manifest.md`.

Or: “Follow editorial-os and blog-post. Topic: …”

## Pipeline

Brief → Research → Outline → Draft → Verify → Publish

- Parallelize **research** (`delegate_task`).
- Single **writer** for final prose; ebook chapters sequential + continuity pass.
- Artifacts under `~/.hermes/content/<genre>/<slug>/`.

## Models

| Stage | Model |
|---|---|
| Research, draft, verify | `xiaomi/mimo-v2.5` only. Do not switch to Sonnet. |

Cron content jobs pin `"model": "xiaomi/mimo-v2.5"`.

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
