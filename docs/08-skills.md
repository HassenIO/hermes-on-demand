# Skills catalog

Custom skills shipped in this repo under [`skills/`](../skills/). Deploy with `make skills-push`. On the VPS they live in `~/.hermes/skills/`.

Invoke in chat with `/skill-name` or ask Hermes to load the skill. Long-form writing: load [`editorial-os`](../skills/content/editorial-os/SKILL.md) with a genre skill — see [Content generation](content-generation.md).

| Category | Count |
|----------|------:|
| Content (long-form) | 7 |
| Research | 1 |
| Tools & web | 1 |
| Job hunting | 2 |
| Productivity & Notion | 10 |
| Memory | 1 |
| **Total** | **22** |

## Content (long-form)

| Skill | Version | Description | SKILL.md |
|-------|---------|-------------|----------|
| `blog-post` | 1.0.0 | Produce a single coherent blog article with locked outline, clear thesis, and editorial-os quality gates. Use for standalone posts, essays, and explainers. | [skills/content/blog-post/SKILL.md](../skills/content/blog-post/SKILL.md) |
| `business-report` | 1.0.0 | Decision-oriented business briefs and reports with methodology, evidence, options, and sources. Use editorial-os. For AI-transformation executive briefs prefer ai-transformation-analyst. | [skills/content/business-report/SKILL.md](../skills/content/business-report/SKILL.md) |
| `course` | 1.0.0 | Create multi-chapter courses with chapters → sections → subsections. Curriculum design under editorial-os — outcomes, scaffolding, Gagné/Merrill, assessments, resumable disk state. | [skills/content/course/SKILL.md](../skills/content/course/SKILL.md) |
| `ebook` | 1.0.0 | Multi-chapter ebook pipeline with disk state, outline lock, sequential chapter drafts, continuity pass, and compile. Uses editorial-os. Resumable across sessions. | [skills/content/ebook/SKILL.md](../skills/content/ebook/SKILL.md) |
| `editorial-os` | 1.0.0 | Shared quality kernel for long-form content. Load with newsletter, blog-post, business-report, ebook, tutorial, or course. Enforces brief→research→outline→draft→verify→publish, epistemics, model routing, and delivery rules. | [skills/content/editorial-os/SKILL.md](../skills/content/editorial-os/SKILL.md) |
| `newsletter` | 1.0.0 | Produce high-quality newsletters and recurring digests. Loads editorial-os pipeline. Use for daily/weekly topic newsletters with sourced items and scannable structure. | [skills/content/newsletter/SKILL.md](../skills/content/newsletter/SKILL.md) |
| `tutorial` | 1.0.0 | Create learning-oriented tutorials with sections and subsections. Diátaxis-style lessons under editorial-os — learn by doing, early wins, one path, minimal explanation, verify before ship. | [skills/content/tutorial/SKILL.md](../skills/content/tutorial/SKILL.md) |

## Research

| Skill | Version | Description | SKILL.md |
|-------|---------|-------------|----------|
| `ai-transformation-analyst` | 0.2.2 | Use when writing executive AI transformation briefs from recent industry shifts. Produces a consultant-grade markdown report by industry and region, with methodology, context-then-problem framing, and a separate expert take. | [skills/research/ai-transformation-analyst/SKILL.md](../skills/research/ai-transformation-analyst/SKILL.md) |

## Tools & web

| Skill | Version | Description | SKILL.md |
|-------|---------|-------------|----------|
| `agent-reach` | 1.0.0 | Read and search the open web via platform CLIs (YouTube, GitHub, RSS, Exa, Bilibili, Jina). Zero-config channels only. | [skills/agent-reach/SKILL.md](../skills/agent-reach/SKILL.md) |

## Job hunting

| Skill | Version | Description | SKILL.md |
|-------|---------|-------------|----------|
| `executive-job-search` | 0.1.0 | CTO/VP Eng job search: market research, CV prep, interviews. | [skills/job-hunting/executive-job-search/SKILL.md](../skills/job-hunting/executive-job-search/SKILL.md) |
| `hiring-agent-sourcing` | 0.1.0 | Source hiring agents from job listings into a Notion DB. | [skills/job-hunting/hiring-agent-sourcing/SKILL.md](../skills/job-hunting/hiring-agent-sourcing/SKILL.md) |

## Productivity & Notion

| Skill | Version | Description | SKILL.md |
|-------|---------|-------------|----------|
| `cron-delivery-config` | 1.0.0 | Set cron delivery targets and Discord thread output. | [skills/productivity/cron-delivery-config/SKILL.md](../skills/productivity/cron-delivery-config/SKILL.md) |
| `cron-job-troubleshooting` | 1.0.0 | Diagnose scheduled cron jobs that error or don't deliver. | [skills/productivity/cron-job-troubleshooting/SKILL.md](../skills/productivity/cron-job-troubleshooting/SKILL.md) |
| `cron-jobs-report` | 1.0.0 | Write a cron jobs report to the Notion Scheduled Jobs page. | [skills/productivity/cron-jobs-report/SKILL.md](../skills/productivity/cron-jobs-report/SKILL.md) |
| `hiring-agents-scraper` | 1.0.0 | Find freelancermap hiring agents and save them to Notion. | [skills/productivity/hiring-agents-scraper/SKILL.md](../skills/productivity/hiring-agents-scraper/SKILL.md) |
| `job-hunting` | 0.1.0 | Search for freelance opportunities matching your profile. | [skills/productivity/job-hunting/SKILL.md](../skills/productivity/job-hunting/SKILL.md) |
| `notion-cron-delivery` | 1.0.0 | Author cron jobs that reliably write to Notion pages. | [skills/productivity/notion-cron-delivery/SKILL.md](../skills/productivity/notion-cron-delivery/SKILL.md) |
| `notion-page-authoring` | 1.0.0 | Write Notion child pages via REST when notion-cli can't. | [skills/productivity/notion-page-authoring/SKILL.md](../skills/productivity/notion-page-authoring/SKILL.md) |
| `notion-reports` | 2.1.0 | Read/write Notion via notion-cli (search, DB rows, template opp creates, reports). | [skills/notion-reports/SKILL.md](../skills/notion-reports/SKILL.md) |
| `notion-skill-sync` | 1.0.0 | Sync custom skills to the Notion Skills page (idempotent). | [skills/productivity/notion-skill-sync/SKILL.md](../skills/productivity/notion-skill-sync/SKILL.md) |
| `user-context-lookup` | 1.0.0 | User info: USER.md → Mnemosyne → sessions. | [skills/productivity/user-context-lookup/SKILL.md](../skills/productivity/user-context-lookup/SKILL.md) |

## Memory

| Skill | Version | Description | SKILL.md |
|-------|---------|-------------|----------|
| `mnemosyne-memory-override` | — | Hard rule override that forces Mnemosyne for all durable memory storage. The legacy memory tool is DEPRECATED for user preferences, credentials, and project conventions. Use memory ONLY for ephemeral session state. | [skills/memory/mnemosyne-memory-override/SKILL.md](../skills/memory/mnemosyne-memory-override/SKILL.md) |

## Related

- [Content generation](content-generation.md) — editorial pipeline
- [Large content task brief](tasks/large-content-generation.md) — research & plan
- [Notion tools](tools/notion.md)
- [Agent-Reach](tools/agent-reach.md)
- [Mnemosyne](tools/mnemosyne.md)
- Upstream: [Hermes skills](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills)

## Ops

```bash
make skills-pull   # VPS → ./skills/
make skills-push   # ./skills/ → VPS (custom only)
```

