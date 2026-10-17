# Large Content Generation — Research, Recommendations, Hermes Plan

**Status:** Implementation started on branch `feature/large-content-generation`  
**Date:** 2026-09-12  
**Owner:** Hassen + Hermes  
**Goal:** Make Hermes excellent at high-quality long-form content: newsletters, blog posts, business reports, ebooks, and similar deliverables.

**Shipped in-repo (skills):** `skills/content/editorial-os`, `newsletter`, `blog-post`, `business-report`, `ebook`, `tutorial`, `course`; Go cron wired; SOUL + `docs/content-generation.md`. Deploy with `make skills-push`, `make push-artifacts`, `make cron-push`.

**Instructional design sources used for tutorial/course:** [Diátaxis tutorials](https://diataxis.fr/tutorials/), [Gagné nine events](https://www.instructionaldesign.org/theories/conditions-learning/), Merrill first principles (problem-centered instruction), [Google Technical Writing One](https://developers.google.com/tech-writing/one) (audience, scope, curse of knowledge).

---

## 1. Executive summary

Hermes today is a strong **personal agent platform** (Telegram/Discord gateway, skills, cron, web research, Notion). It is **not yet a long-form content factory**. Quality peaks in one skill (`ai-transformation-analyst`); recurring content (e.g. Go newsletter) is under-engineered; blogs and ebooks have no first-class pipeline.

Industry and research consensus is clear:

1. **Do not one-shot long documents** from a vague prompt.
2. **Separate research from writing**; parallelize research only; write with a single coherent author pass.
3. **Lock an outline** before prose.
4. **Verify against a checklist** (and optionally a second editor pass) before delivery.
5. **Manage context aggressively** (summaries, files on disk, subagents that return digests).
6. **Use a stronger model for draft + verify**; cheaper models are fine for search and inventory.

**Decided direction (from planning):**

| Decision | Choice |
|---|---|
| First build | Shared **editorial OS** + **genre skills** (newsletter, blog, business report, ebook) |
| Content types (1–2 months) | All four |
| Models | Always stronger model on **write + verify**; default/flash OK for research |

This document is the master reference for findings, recommendations, and how that maps onto this repo.

---

## 2. Current Hermes baseline

### 2.1 What this repo is

Infrastructure-as-code / control plane for [Nous Research Hermes Agent](https://hermes-agent.nousresearch.com/) on an Ubuntu VPS. The local machine deploys config, secrets, skills, and cron over SSH. Content is produced by **agent runs + skills + tools**, not a dedicated CMS.

| Layer | Role |
|---|---|
| Gateway | Telegram (primary), optional Discord |
| Model | OpenRouter; default today `xiaomi/mimo-v2.5` (flash-class) |
| Skills | `SKILL.md` playbooks under `skills/` → `~/.hermes/skills/` |
| Cron | Fresh headless session per job; delivery to Discord/Telegram/Notion/local |
| Web | SearXNG + Firecrawl lite |
| Terminal | Docker sandbox |
| Memory | Mnemosyne; built-in USER/MEMORY injection mostly off |
| Notion | `notion-cli` + page-authoring skills |

Upstream runtime features that matter for long-form (available on the agent, to be used via skills/prompts):

- Progressive disclosure skills (`skills_list` → `skill_view` → references)
- `delegate_task` subagents (isolated context; summaries only back)
- `execute_code` for mechanical gather-then-analyze
- Cron with per-job model pin and skill attachment
- `/learn` for knowledge-base skills
- Skill bundles (group skills under one slash command)
- File-backed state across sessions

### 2.2 Existing content-related assets

| Asset | Type | Quality depth |
|---|---|---|
| `skills/research/ai-transformation-analyst/` | Executive AI strategy briefs | **Highest** — assignment contract, geo/industry procedure, epistemics, fixed template, verification gate, 1.8–2.8k words |
| `skills/productivity/job-hunting/` | Opportunity digests | Medium — structure, tiers, filters |
| `skills/job-hunting/executive-job-search/` | Strategy packages | Medium–long |
| Cron: Go/Baduk Daily Newsletter | Newsletter | Short; **prompt-only, no skill**, fragile Notion path |
| `skills/productivity/notion-page-authoring/` | MD → Notion blocks | Delivery, not generation |
| `skills/productivity/notion-cron-delivery/` | Resilient cron → Notion | Ops pattern |
| `artifacts/SOUL.md` | Persona | 5 lines; no house writing voice |

### 2.3 Quality patterns already proven in-repo

Reuse these; do not reinvent:

1. **Assignment contract** + defaults (headless-safe)
2. **Numbered procedure** with hard gates (“do not write before step N”)
3. **Fixed heading template**
4. **Verification checklist** before deliver
5. **Standing pitfalls** list
6. **Epistemics** — opened URL only; source classes; two-source for load-bearing claims; absence as finding
7. **Fact vs judgment** separation
8. **Word-count band** + banned empty verbs
9. **Tier/confidence** systems (job-hunting)
10. **Cron self-contained prompts** (no chat memory)
11. **Idempotent Notion** replace + chunked blocks
12. **Toolset scoping** and **model pin** on cron

### 2.4 Gaps for large content

| Gap | Impact |
|---|---|
| No shared editorial OS | Every skill reinvents voice, citations, verify |
| No blog / ebook skills | Ad-hoc quality only |
| No multi-pass pipeline as a product | Research + draft + edit share one messy session |
| Newsletter under-engineered | Best recurring content product is weakest skill-wise |
| Single-pass generation default | Context rot, shallow research, weak structure |
| Flash model default for everything | Weak sustained multi-thousand-word coherence |
| Chat as primary UX for long form | Discord ~2k chunks; poor reading experience |
| `notion-cli create-report` = paragraphs only | Structure lost unless page-authoring used |
| No chapter/outline state machine | Ebooks and multi-part series cannot resume cleanly |
| SOUL has no writing standards | Voice drifts |

---

## 3. Research findings (what is proven effective)

### 3.1 Agent architectures for long work

**Source:** [Anthropic — Building effective agents](https://www.anthropic.com/research/building-effective-agents)

- Prefer **simple composable patterns** over heavy frameworks.
- Distinguish **workflows** (fixed code paths) vs **agents** (model directs tool use).
- Patterns that map directly to content:

| Pattern | Content use |
|---|---|
| Prompt chaining | Outline → draft → polish |
| Routing | Genre / length / model selection |
| Parallelization (sectioning) | Parallel **research** topics |
| Parallelization (voting) | Multi-critic review (optional) |
| Orchestrator–workers | Supervisor + research subagents |
| Evaluator–optimizer | Writer + editor loop with clear criteria |

**Principle:** Add multi-step complexity only when it measurably improves outcomes.

### 3.2 Context engineering (the real bottleneck)

**Source:** [Anthropic — Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

- Context is a **finite attention budget**; long contexts suffer **context rot**.
- Goal: **smallest high-signal token set** for the desired behavior.
- System prompts: right altitude (not brittle if-else, not vague).
- Tools: minimal, non-overlapping, token-efficient returns.
- Few-shot: few **canonical** examples, not endless edge cases.
- Long-horizon tactics:
  - **Compaction** (summarize and continue)
  - **Structured note-taking** outside the window (`progress.json`, `outline.md`)
  - **Subagents** that explore heavily and return **short digests**

Hermes already supports the last two via files + `delegate_task`. Skills must **require** them for long jobs.

### 3.3 Deep research → report systems

#### STORM (Stanford, NAACL 2024)

**Paper:** [arXiv:2402.14207](https://arxiv.org/abs/2402.14207)  
**Code:** [github.com/stanford-oval/storm](https://github.com/stanford-oval/storm)

Pipeline:

1. **Pre-writing:** multi-perspective research + simulated expert Q&A grounded on web sources → outline  
2. **Writing:** outline + sources → full article with citations  
3. **Polish:** optional

Results vs outline-driven RAG baseline: **+25% organized**, **+10% broad coverage** (editor judgments). Remaining hard problems: source bias transfer, over-association of unrelated facts.

**Co-STORM** (EMNLP 2024): human–AI collaborative discourse + mind map for deeper aligned research — useful later for interactive ebook/report commissioning.

#### LangChain Open Deep Research

**Blog:** [Open Deep Research](https://blog.langchain.com/open-deep-research/)  
**Code:** [langchain-ai/open_deep_research](https://github.com/langchain-ai/open_deep_research)

Three phases:

1. **Scope** — clarify user need → compress into a **research brief** (north star)  
2. **Research** — supervisor + parallel subagents; each returns **cleaned findings + citations** (not raw scrapes)  
3. **Write** — **one-shot report** from brief + findings  

Critical lesson (matches Cognition’s multi-agent warning):

> **Parallelize research. Do not parallel-write report sections.** Section writers produce disjoint prose. One writer after research is done.

Also: multi-agent helps when subtopics would **clash in one context window**; supervisor tunes depth so simple asks stay fast.

#### Anthropic multi-agent research

**Source:** [How we built our multi-agent research system](https://www.anthropic.com/engineering/built-multi-agent-research-system)

- Lead agent plans; subagents search in isolation.
- Token cost is high (~15× chat); context hygiene is mandatory.
- Subagents return condensed results to the lead.

### 3.4 Prompting craft (models)

**Claude:** [Prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices)

- Clear, direct, sequential steps; explain *why* constraints exist  
- XML structure for mixed instructions/context/examples  
- Role prompts; long docs **above** the query; quote-then-answer for grounded writing  
- Explicit output format; self-check against criteria before finish  
- Parallel tool calls for independent research  

**OpenAI:** [Prompt engineering](https://platform.openai.com/docs/guides/prompt-engineering) · [GPT-5 prompting guide](https://cookbook.openai.com/examples/gpt-5/gpt-5_prompting_guide)

- Developer vs user role hierarchy; Markdown + XML boundaries  
- Few-shot diversity; pin model snapshots  
- Persistence + plan-before-act for agents  
- **Self-reflection rubric** before one-shot deliverables (web apps; transferable to articles)  
- Avoid contradictory instructions (reasoning models thrash)  
- Verbosity and reasoning_effort as separate controls  

**DAIR Prompt Engineering Guide:** CoT, Tree-of-Thoughts, prompt chaining, RAG, Reflexion — useful as technique vocabulary; ToT is heavy for most prose (better for hard planning), chaining + evaluator loop is the workhorse for writing.

### 3.5 Hermes-native docs (use as product constraints)

| Doc | Takeaway for content |
|---|---|
| [Skills system](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills) | Progressive disclosure; references/; agent-managed skills; bundles |
| [Work with skills](https://hermes-agent.nousresearch.com/docs/guides/work-with-skills) | Focused skills; procedures + pitfalls + verification |
| [Delegation patterns](https://hermes-agent.nousresearch.com/docs/guides/delegation-patterns) | Parallel research; gather-then-analyze; full context in `goal`/`context` |
| [Daily briefing bot](https://hermes-agent.nousresearch.com/docs/guides/daily-briefing-bot) | Cron = fresh session; **self-contained prompts**; persona in prompt |
| [Tips](https://hermes-agent.nousresearch.com/docs/guides/tips) | Specificity; AGENTS/SOUL; skills vs memory; model switch cost (cache) |
| [SOUL guide](https://hermes-agent.nousresearch.com/docs/guides/use-soul-with-hermes) | Short durable voice; procedures stay in skills |

### 3.6 Editorial craft (non-ML but required)

Encode as skill rules, not vibes:

- Audience and **decision/outcome** first  
- Outline lock before draft  
- One idea per paragraph; concrete nouns; kill empty verbs  
- Separate research notes from draft prose  
- Fact vs opinion labeled  
- Citations with publisher, date, URL actually opened  
- Length band as quality control (forces selection)  
- Final pass: structure, claims, continuity, banned language  

### 3.7 Synthesis — the universal quality pipeline

```
BRIEF          audience, goal/decision, length, tone, sources, headless defaults
    ↓
RESEARCH       parallel subagents OK → findings.md + sources.md (cleaned)
    ↓
OUTLINE        lock structure (user approve if interactive)
    ↓
DRAFT          single writer; strong model; section-by-section if very long
    ↓
VERIFY         checklist ± second-pass editor; revise until pass
    ↓
PUBLISH        file + structured Notion; chat/Discord = teaser + link only
```

**Filesystem state** for anything multi-session (especially ebooks):

```
~/.hermes/content/<genre>/<slug>/
  brief.md
  outline.md
  findings.md
  sources.md
  draft.md          # or chapters/
  progress.json
```

---

## 4. Recommendations (prioritized)

### 4.1 Product recommendations

| Priority | Recommendation | Rationale |
|---|---|---|
| P0 | Build **editorial-os** skill as shared quality kernel | One place for epistemics, verify, voice, model routing, publish |
| P0 | Build four **genre skills** that load editorial-os | Newsletter, blog, business-report, ebook |
| P0 | **Stronger model on draft + verify** always | Flash is fine for search; not for 2k–20k word decision-grade prose |
| P1 | Migrate **Go newsletter** cron onto newsletter skill + model pin | Prove the system on a live product |
| P1 | Publish contract: **file + notion-page-authoring**; never long walls in chat | Matches channel limits and Notion structure |
| P2 | Light **SOUL** lines pointing at content skills | Discoverability without prompt bloat |
| P2 | Cross-link **ai-transformation-analyst** → editorial-os | Don’t fork epistemics forever |
| P3 | Optional **deep-research** thin orchestrator (STORM-like) | After genres work; can live inside business-report first |
| P3 | Few-shot gold examples per genre in `references/` | Highest ROI after procedures stabilize |
| Later | LLM-as-judge eval set | Only after manual smoke tests show stable output |

### 4.2 What not to do

- Do not build a separate multi-agent framework outside Hermes — use skills + `delegate_task` + files.  
- Do not parallel-write chapters/sections as the final draft without a continuity pass.  
- Do not put the entire editorial manual in SOUL or one mega-skill (token death).  
- Do not use `notion-cli create-report` for structured long docs.  
- Do not rely on chat memory for cron content.  
- Do not change the **global** default chat model to an expensive frontier model, and do not pin Sonnet for a stage. Chat, cron, and long-form content use `model.default`.

### 4.3 Model routing policy (superseded)

Superseded. Chat, cron, and long-form content use `model.default` in `config/config.yaml.example`. Do not pin Sonnet. See `docs/content-generation.md`. Do not set a different model on a cron job unless the user asked for that override.

### 4.4 Genre-specific quality bars

| Genre | Length band (default) | Structure | Research depth | Continuity |
|---|---|---|---|---|
| Newsletter | 400–1,200 words | Hook → items → optional dive → close | High freshness, shallow–medium | Series: optional prior-issue note |
| Blog post | 1,200–2,500 | Thesis + H2/H3 outline → narrative | Medium | Single piece |
| Business report | 1,500–3,000 short; 3,000–6,000 full | Decision-first; methodology; findings; options; sources | High | Single piece or series |
| Ebook | Per chapter 1,500–3,000; N chapters | TOC lock → sequential chapters → compile | High, multi-session | **Required** progress.json + voice pass |

---

## 5. Implementation plan for Hermes

### 5.1 Design principles (implementation)

1. **Skills-first** — all quality lives in `skills/content/**` deployable via existing `make` / skills-push.  
2. **Progressive disclosure** — lean `SKILL.md`; detail in `references/`.  
3. **Hard gates in procedure text** — “Do not write before outline. Do not deliver before verification.”  
4. **Headless-safe** — defaults for every assignment field; no questions on cron.  
5. **Reuse** AI analyst, notion-page-authoring, notion-cron-delivery, delegation patterns.  
6. **State on disk** under `~/.hermes/content/` for multi-step and ebook.  
7. **Bundles** (or explicit “load editorial-os first”) so one slash command loads the stack.

### 5.2 Target directory layout

```
skills/content/
  editorial-os/
    SKILL.md
    references/
      house-voice.md
      epistemics.md
      verification-universal.md
      banned-language.md
      model-routing.md
      publish-contract.md
      pipeline.md
      # later: few-shot/*.md
  newsletter/
    SKILL.md
    references/
      template.md
      verification.md
  blog-post/
    SKILL.md
    references/
      template.md
      verification.md
  business-report/
    SKILL.md
    references/
      template.md
      verification.md
  ebook/
    SKILL.md
    references/
      template-chapter.md
      state-machine.md
      verification.md

docs/
  content-generation.md          # user-facing how-to (after skills exist)
  tasks/
    large-content-generation.md  # this file

artifacts/
  SOUL.md                        # minimal pointer lines only

cron/
  jobs.json                      # Go newsletter → skill + strong model
```

Optional later:

```
~/.hermes/skill-bundles/
  content-newsletter.yaml
  content-blog.yaml
  content-report.yaml
  content-ebook.yaml
```

(If bundles are managed only on VPS, document creation commands in `docs/content-generation.md`.)

### 5.3 Phase 1 — Editorial OS (foundation)

**Create** `skills/content/editorial-os/`.

#### SKILL.md responsibilities

- **When to use:** Any long-form content; always load before or with a genre skill.  
- **Assignment contract** table:

  | Field | Default |
  |---|---|
  | topic | required (halt if missing in headless) |
  | audience | informed professional reader |
  | goal / decision | infer or “inform clearly” |
  | length | from genre skill |
  | tone | clear, concrete, non-hype |
  | sources | web + provided; opened pages only |
  | output | markdown file under `~/.hermes/content/...` + reply summary |
  | mode | headless if cron/one-shot |

- **Pipeline law** (must appear early): Brief → Research → Outline → Draft → Verify → Publish.  
- **Research:** Prefer `delegate_task` for independent topics; write cleaned findings to disk; never treat memory as evidence.  
- **Writing:** Single final author; no parallel final section writers without a continuity pass.  
- **Verify:** Run universal checklist; revise until pass.  
- **Model routing:** Switch to / pin strong model before draft; stay on it through verify.  
- **Publish:** Follow publish-contract reference.

#### Reference files

| File | Purpose |
|---|---|
| `pipeline.md` | Expanded stage definitions and disk artifacts |
| `epistemics.md` | Source classes, two-source rule, absence-as-finding, no memory-as-evidence |
| `verification-universal.md` | Master checklist shared by all genres |
| `banned-language.md` | leverage, unlock, revolutionize, seamless, etc. |
| `house-voice.md` | Short voice: direct, concrete, executive-readable, no throat-clearing |
| `model-routing.md` | Exact OpenRouter IDs for research vs write; cron pin examples |
| `publish-contract.md` | Paths, Notion page-authoring, chat teaser rules, `[[as_document]]` if useful |

#### Acceptance criteria (Phase 1)

- [ ] Skill installs and appears in `skills_list`  
- [ ] Agent loads references on demand via `skill_view`  
- [ ] Contract + pipeline + verify are unambiguous in one read of SKILL.md  

### 5.4 Phase 2 — Genre skills

Each genre skill:

1. Declares **When to use**  
2. States **Load `editorial-os` first** (or bundle)  
3. Defines assignment overrides (length, template, freshness)  
4. Genre procedure steps  
5. Points to `references/template.md` + `references/verification.md`  
6. Headless contract  

#### 2a. Newsletter

- Template: date header → hook → N items (headline, 2–3 sentences, link, why it matters) → optional deep dive → footer (sources count)  
- Freshness default: last 24–72h  
- Research: parallel topics OK  
- **Migrate** `Go/Baduk/Weiqi Daily Newsletter` in `cron/jobs.json`:
  - Attach newsletter skill (and editorial-os via instructions/bundle)
  - Replace fragile Notion markdown field with page-authoring pattern where possible
  - Pin **strong model**
  - Keep Discord delivery as short/scannable or teaser + Notion link if length grows

#### 2b. Blog post

- Template: title options → dek → intro (problem) → body H2s → conclusion → optional sources  
- Require outline approval in interactive mode; auto-lock outline in headless  
- Optional light SEO block (title ≤60 chars, meta description, slug) — secondary to quality  
- Single narrative; no “listicle sludge” unless assignment asks for list form  

#### 2c. Business report

- Generalize AI analyst patterns without the AI-only domain lock  
- Sections: header table (decision, question, window) → methodology → executive summary/pulse → findings → options → recommendation (judgment) → sources  
- Length bands: short vs full  
- For **AI transformation** topics: prefer or chain `ai-transformation-analyst` (domain specialist) rather than diluting it  
- High epistemic bar (same as editorial-os)  

#### 2d. Ebook

- State machine in `references/state-machine.md`  
- Directory: `~/.hermes/content/ebooks/<slug>/`  
  - `brief.md`, `outline.md`, `toc.json`, `chapters/NN-slug.md`, `progress.json`, `manuscript.md`  
- Steps: brief → outline lock → research pack (optional shared findings) → write chapter N → update progress → until done → continuity pass → compile  
- Resume: on fresh session, read `progress.json` first  
- Never claim book complete if chapters missing  
- Strong model for every chapter draft + final continuity  

#### Acceptance criteria (Phase 2)

- [ ] Each genre produces a file matching its template in a manual run  
- [ ] Verification checklists are genre-specific supersets of universal  
- [ ] Ebook can pause after chapter 1 and resume chapter 2 in a new session  

### 5.5 Phase 3 — Wiring, persona, docs, specialist cross-links

| Task | Detail |
|---|---|
| Skill bundles | Create four bundles if Hermes bundle path is used on VPS; else document `/editorial-os` + `/newsletter` stacking |
| `cron/jobs.json` | Go newsletter migration |
| `artifacts/SOUL.md` | 3–5 lines: long-form uses `content/*` skills; deliver files/Notion not chat walls; never invent sources |
| `skills/research/ai-transformation-analyst/SKILL.md` | Short note: follow editorial-os if loaded; do not duplicate conflicting rules |
| `docs/content-generation.md` | How to invoke, models, paths, cron examples, Notion |
| `config/config.yaml.example` | Comment documenting recommended `content_write_model` convention (even if only used in cron pins) |

### 5.6 Phase 4 — Validation

Manual smoke tests (no automated harness in v1):

| # | Test | Pass condition |
|---|---|---|
| 1 | Interactive blog on a known topic | Outline then draft; verify language; file on disk |
| 2 | Newsletter headless-style single prompt | No clarifying questions; real URLs; length band |
| 3 | Business report short | Decision in header; methodology; sources opened |
| 4 | Ebook mini (2 chapters) | progress.json advances; voice consistent after continuity |
| 5 | Go newsletter prompt dry-run | Skill path clear; model pin present in job |
| 6 | Notion publish path | Headings/lists preserved (page-authoring) |

Deploy: `make skills-push` (or project-equivalent) + cron push after job edit + `make push-artifacts` for SOUL.

### 5.7 Implementation order (execution checklist)

1. Write `editorial-os` SKILL + references  
2. Write `newsletter` + migrate Go cron  
3. Write `business-report`  
4. Write `blog-post`  
5. Write `ebook` + state machine  
6. SOUL + docs + analyst cross-ref + config comment  
7. Bundles (if applicable)  
8. Smoke tests + deploy  

### 5.8 Mapping research → concrete Hermes mechanisms

| Research idea | Hermes mechanism |
|---|---|
| STORM pre-writing / multi-perspective Q | Procedure steps + parallel `delegate_task` with perspective goals |
| Open Deep Research brief | `brief.md` artifact; compress chat into brief before research |
| Supervisor + sub-researchers | Parent agent + `delegate_task`; cleaned findings files |
| One-shot write after research | Genre draft step; single writer |
| Evaluator–optimizer | Verification checklist; optional second pass “editor” instructions in same or fresh session |
| Context engineering / notes | `~/.hermes/content/...` files; progress.json |
| Subagent summary-only | Native delegation behavior |
| Progressive disclosure | SKILL.md + references/ |
| Cron self-contained | Genre headless contract + full prompt body |
| Strong model on write | Skill model-routing + cron `model:` pin |
| House style | house-voice.md + light SOUL |
| Structured publish | notion-page-authoring skill |
| Knowledge base for niche domains | `/learn` or references/ under genre or topic skills later |

### 5.9 Risks and mitigations

| Risk | Mitigation |
|---|---|
| Skills too long → ignored | Lean SKILL.md; details in references; agent must `skill_view` references when needed |
| Agent skips verification | Gate language + pitfalls; verification as mandatory step before any deliver tool |
| Still uses flash for draft | model-routing.md + cron pin; verify step checks “write model” instruction was followed |
| Ebook context death mid-book | progress.json + chapter files; resume procedure |
| Notion block limits | Chunked append via existing authoring scripts |
| Cost spike on strong model | Strong model only draft/verify; research stays cheap; length bands |
| Conflict with AI analyst rules | Specialist wins on AI transformation domain template; shared epistemics only |
| Bundle/skill name collisions | Prefix `content-` or directory category `content/` |

### 5.10 Success metrics (qualitative v1)

- Recurring newsletter runs **without** manual repair of structure or empty sources.  
- Business briefs approach AI-analyst readability (decision-first, sourced, verified).  
- Blog posts have locked outlines and coherent arcs (no mid-article topic drift).  
- Ebook can be commissioned and resumed across days without re-briefing from zero.  
- Operator (Hassen) prefers file/Notion output over chat paste for anything >~800 words.

---

## 6. Canonical resource library

Keep these as the external reference set when iterating skills.

### Hermes

- https://hermes-agent.nousresearch.com/docs/user-guide/features/skills  
- https://hermes-agent.nousresearch.com/docs/guides/work-with-skills  
- https://hermes-agent.nousresearch.com/docs/guides/delegation-patterns  
- https://hermes-agent.nousresearch.com/docs/guides/daily-briefing-bot  
- https://hermes-agent.nousresearch.com/docs/guides/tips  
- https://hermes-agent.nousresearch.com/docs/guides/use-soul-with-hermes  
- https://hermes-agent.nousresearch.com/docs/guides/automate-with-cron  
- In-repo gold standard: `skills/research/ai-transformation-analyst/SKILL.md`

### Agents and context

- https://www.anthropic.com/research/building-effective-agents  
- https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents  
- https://www.anthropic.com/engineering/built-multi-agent-research-system  

### Long-form generation systems

- https://arxiv.org/abs/2402.14207 (STORM)  
- https://arxiv.org/abs/2408.15232 (Co-STORM)  
- https://github.com/stanford-oval/storm  
- https://blog.langchain.com/open-deep-research/  
- https://github.com/langchain-ai/open_deep_research  

### Prompting

- https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices  
- https://platform.openai.com/docs/guides/prompt-engineering  
- https://cookbook.openai.com/examples/gpt-5/gpt-5_prompting_guide  
- https://www.promptingguide.ai/  

---

## 7. Open items before/during build

1. **Exact OpenRouter model ID** for write/verify (primary + fallback) — fill into `model-routing.md`.  
2. Confirm VPS disk path writable from Docker sandbox for `~/.hermes/content/` (may need volume mount in `config.yaml`).  
3. Confirm how this deploy pushes skills (`make skills-push` / rsync) and bundles.  
4. Whether Go newsletter should stay Discord-full-text or move primary body to Notion with Discord teaser.  
5. Optional: raise terminal timeout for deep research crons only.

---

## 8. Document history

| Date | Change |
|---|---|
| 2026-09-12 | Initial research synthesis, recommendations, and Hermes implementation plan |

---

## 9. Next action

When ready to implement: execute **§5.7** starting with `skills/content/editorial-os/`, using this doc as the spec. Do not expand scope to a separate research framework until the four genres + editorial-os pass smoke tests.
