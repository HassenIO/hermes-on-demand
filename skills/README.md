# skills

Custom Hermes skills. Skill files are not committed. This README, and a README in each subfolder, are the only Git files under `skills/`.

A skill is a directory with `SKILL.md`. Hermes loads it when you use `/<skill-name>` or ask it to load that skill.

Edit on the local machine, then install on the VPS:

```bash
make skills-push
```

Pull VPS edits (including ones the agent wrote) back here:

```bash
make skills-pull
```

The VPS copy is `~/.hermes/skills/`. The S3 watcher mirrors custom skills from there. Builtin Hermes skills are not in this tree.

Packages:

- `agent-reach`
- `content/blog-post`
- `content/business-report`
- `content/course`
- `content/ebook`
- `content/editorial-os`
- `content/newsletter`
- `content/tutorial`
- `job-hunting/contract-hunt-dubai`
- `job-hunting/executive-job-search`
- `job-hunting/hiring-agent-sourcing`
- `job-hunting/justjoin-scraping`
- `memory/mnemosyne-memory-override`
- `notion-reports`
- `productivity/cron-delivery-config`
- `productivity/cron-job-troubleshooting`
- `productivity/cron-jobs-report`
- `productivity/hiring-agents-scraper`
- `productivity/job-hunting`
- `productivity/notion-cron-delivery`
- `productivity/notion-page-authoring`
- `productivity/notion-skill-sync`
- `productivity/user-context-lookup`
- `research/ai-transformation-analyst`
