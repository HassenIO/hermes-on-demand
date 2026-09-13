# Tutorial & course skills — design notes

**Date:** 2026-09-12  
**Skills:** `skills/content/tutorial/`, `skills/content/course/`

## Hierarchy

| Genre | Structure |
|---|---|
| **Tutorial** | `#` title → `##` sections → `###` subsections |
| **Course** | Course → **chapters** → `##` sections → `###` subsections |

## Best sources used

1. **[Diátaxis — Tutorials](https://diataxis.fr/tutorials/)** — Learning-oriented lessons; learn by doing; early results; expected narrative; minimize explanation; one path; reliability; “we” language. Distinguishes tutorial vs how-to.
2. **[Gagné — Conditions of Learning / nine events](https://www.instructionaldesign.org/theories/conditions-learning/)** — Attention, objective, recall, present, guide, elicit, feedback, assess, transfer. Learning hierarchies / prerequisites.
3. **Merrill — First principles of instruction** — Problem-centered; activation, demonstration, application, integration (applied especially at course/chapter level).
4. **[Google Technical Writing One](https://developers.google.com/tech-writing/one)** — Audience, scope/non-scope, curse of knowledge, key points early, clear structure, consistent terms.

## Why not only ebook?

Ebooks optimize for long-form reading. Tutorials/courses optimize for **skill acquisition**, practice, checks, and (for courses) curriculum sequencing. Shared kernel remains `editorial-os`.

## Visuals (v1.1)

Mandatory instructional figures for tutorials and courses — see `skills/content/editorial-os/references/instructional-visuals.md`.

| Requirement | Tutorial | Course chapter |
|---|---|---|
| Destination / overview figure | Yes (top) | Yes (chapter start) |
| Explanatory visual per teaching section | Yes | Yes |
| Production | `image_generate` → `assets/`; Mermaid fallback | Same, `chNN-` prefix |
| Verify | alt + caption + manifest | Same + style continuity |

Rationale: Gagné “present stimulus” / Merrill “demonstrate” need something to see; dual coding (words + diagram) improves concept learning without turning the lesson into a lecture.

### v1.2 — Web download path

1. Collect figure URLs → `assets/candidates.md`
2. **`curl` / `fetch_asset.sh`** into local `assets/`
3. Else `image_generate` + save locally
4. Else Mermaid
5. `test -s` on every path

### v1.3 — Bookends, resources, freshness, real images

| Addition | Detail |
|---|---|
| Course **introduction** | Why, who, value, finish benefits, chapter table, **mind map** |
| Course **conclusion** | Learned, apply, what’s next, full resource index |
| **Resources used** | End of every chapter + tutorial; inline deep links in body |
| **Freshness** | Mandatory live search; no stale model/tool names from memory |
| **Images** | Mermaid-only fails if web download or gen was possible; prefer downloaded docs figures |

Helper: `skills/content/editorial-os/scripts/fetch_asset.sh`  
Freshness: `skills/content/editorial-os/references/freshness.md`
