# Epic Feasibility Analysis — Reusable Guide

A repeatable method for assessing whether a product epic can be delivered against the current SBE codebase, which repos must change, what can't be delivered, the open questions for the BA, and the cross-epic dependencies. Produced once for **Epic 13 — Order History (Exhibitor)**; this guide generalizes that process so any session can run it for a new epic.

> **Worked example:** see `order_history/` — `Order History - Feasibility Analysis (Consolidated).xlsx` (7 sheets) + `Order History - Feasibility Summary.md`. Use it as the reference output shape.

---

## 0. Context you must know first

- **Five NestJS backends share ONE PostgreSQL DB:** `admin-backend-api`, `exhibitor-backend-api`, `background-worker-service`, `external-api-service`, `pulse-broker-service`.
- **`admin-backend-api/prisma/schema.prisma` is the SOURCE OF TRUTH** for the data model (it owns migrations). The other four run `db push`. Always verify data-model claims against this file.
- Feature branches are cut from `dev`. Node 24.
- **Each sub-folder is its own git repo.**

## When to use this
The user asks: "can epic X be delivered with the current codebase", "what's the feasibility of epic X", "which repos need changes for X", "what can't we deliver", "what should we ask the BA". The deliverable is an analysis, **not** code.

---

## 1. Inputs to gather

1. **Requirement source(s)** — usually an `.xlsx` (BA user stories: System Specification / Design Specification / Validation columns) and/or a `.pdf` of the full story set. Find them in a per-epic folder (e.g. `order_history/`) or ask the user.
2. **Referenced/linked stories** — requirements often say "Refer User Story <name>". These may live in a separate full-stories PDF, not the epic xlsx. Locate and fold them in (Step 5) — they frequently resolve or reframe gaps.
3. **The codebase** — all 5 repos under the APIs root.

### Reading the sources (tooling gotchas)
- `.xlsx`: use Python `openpyxl` (already available). `pandas` is NOT installed.
- `.pdf`: the Read tool needs `poppler` which is NOT installed (no `pdftotext`/`pdftoppm`). Instead `pip install --quiet pypdf pdfplumber` and extract text. PDFs here are **two-column**, so plain extraction interleaves columns — use `pdfplumber` `extract_text(layout=True)` and clean whitespace, or extract per page and locate stories by title/phrase before reading the specific pages.
- Big PDFs (the exhibitor story set is ~540 pages): extract all page text once to a scratch file, grep for story titles/phrases to find page numbers, then read only those ranges. Don't read the whole PDF.

---

## 2. Decompose requirements into atomic sub-requirements

Read every story and break it into **atomic, individually-testable sub-requirements** (a column, an action, a field, a rule). Order History 13.1–13.3 → 59 atomic items. Each becomes one row to be judged. Capture: `reqId` (e.g. 13.2), `reqTitle`, `subRequirement` (the atomic ask).

---

## 3. Run the analysis as an ultracode workflow

This is a large multi-repo read; orchestrate it. Requires the user to have opted into multi-agent orchestration (keyword **ultracode**, or they ask for a workflow). Three phases:

1. **Scan repos** — one agent per repo (+ a schema deep-dive agent on the admin source-of-truth schema). Each returns a structured capability inventory relevant to the epic: relevant models (name, key fields, purpose), modules, and capabilities marked `present | partial | absent` with file/model evidence.
2. **Feasibility** — one agent per requirement cluster (group the atomic items into ~8 clusters). Each consumes the Phase-1 inventory digest and judges every atomic sub-requirement with a verdict + repos-impacted + gap + evidence + an open question.
3. **Verify gaps** — adversarially re-check **every** non-`Deliverable` verdict: the agent is told to try to PROVE THE GAP WRONG (find the model/field/service that would make it deliverable) before agreeing it's missing. This catches false negatives — e.g. for Order History a quick grep "found no payment plan", but verification found installments DO exist as `PaymentTransaction` rows with `due_date`/`status`.

Default to `pipeline()`/`parallel()`. Pass Phase-1 results into Phase-2 prompts as a text digest (agents don't share memory). Return `{ scans, feasibilityItems, verifications }` as structured JSON. The workflow script template is in **Appendix A**.

> If the user has NOT opted into orchestration, do a lighter single-pass version: scan the schema + relevant modules yourself, judge the items, and spot-verify the gaps. Same taxonomy and outputs.

### Verdict taxonomy (use exactly these)
- **Deliverable** — data + relations exist; needs new API/UI build only (no data-model gap).
- **Partial** — partly supported; a key field/relation/service is missing or must be derived.
- **NotDeliverable** — core data model/service does not exist in any repo today.
- **NeedsClarification** — ambiguous, or depends on a referenced story / architectural decision.

---

## 4. Apply the verifications & compute repo impact

- Override each item's verdict with its verification result (an item can move e.g. `Partial → Deliverable` if the verifier found the data).
- **Repo impact:** aggregate `reposImpacted` across all gap (non-Deliverable) items. State which repos beyond the primary one need changes, and explicitly call out any repo that is **not** impacted (e.g. pulse-broker-service was untouched by Order History).
- Identify the **primary repo** (the one the epic's feature lives in). For Order History it was `exhibitor-backend-api`, where the feature was net-new (no existing module).

---

## 5. Reconcile referenced/external stories

For every "Refer User Story <name>", locate that story (Step 1.2) and fold its content in. This usually:
- **Resolves** a `NeedsClarification` (the data contract becomes known) → often `→ Partial`.
- **Confirms** a gap with authority (e.g. stories said onsite contact is "at the order level" but the schema keys it `(company, show)` → confirmed linkage gap).
- **Reframes** scope (e.g. a referenced payment story turned out to be checkout-time, so it did NOT resolve the "early-pay" gap).

Record what each referenced story changed, with PDF page citations.

---

## 6. Classify cross-epic dependencies (out-of-scope blockers)

Some sub-requirements can't be delivered until an **out-of-scope** epic produces the data. Document these as a dependency register so they're not mistaken for in-epic work. Columns: dependency (epic/story), what this epic needs from it, the gated item(s), **type**, impact if not delivered, likely owner/repo.
- **Hard (blocks)** — cannot deliver the gated item at all until upstream delivers (no data/source exists).
- **Soft (workaround)** — can build a fallback now; cleaner once upstream lands.
- **Architectural** — a cross-cutting design decision (e.g. a "centralized billing/pricing service" referenced across epics but not built).

---

## 7. Produce the deliverables

One **consolidated `.xlsx`** named `<Epic> - Feasibility Analysis (Consolidated).xlsx` in the epic's folder, plus a `<Epic> - Feasibility Summary.md` narrative companion. The workbook has these sheets (see the Order History file for exact formatting — frozen header row, colour-coded verdict/priority/type columns):

1. **Overview** — sources, method, verdict counts, repos impacted (+ not-impacted), hard blockers, sheet index, colour legend.
2. **Analysis Summary** — bottom line + what the referenced stories changed + gap themes.
3. **All Requirements (N)** — every atomic requirement with its verdict (colour-coded), gap, referenced-story finding, evidence.
4. **Not Fully Deliverable** — the non-Deliverable subset, grouped by theme, with gap + story finding + evidence + repos-to-change.
5. **Open Questions for BA** — consolidated, deduped, prioritized (High/Medium/Low), each with what it blocks.
6. **Cross-Epic Dependencies** — the register from Step 6.
7. **Referenced Stories** — extracts of the referenced stories with PDF page refs and this-epic impact.

**Colour convention:** Orange = blocker / High / Hard; Yellow = Partial / Medium / Soft; Blue = NeedsClarification / Architectural; Green = Deliverable / Low.

The xlsx-generation Python (openpyxl) is reusable — copy `order_history/`'s generator approach (styling helpers `style_header`/`finalize`, `VERDICT_FILL`/`PRI_FILL`/`TYPE_FILL` maps).

### Optional: endpoint count
If asked how many endpoints the epic needs, derive the API surface from the stories' actions (list, detail, per-action downloads, mutations). State it as an estimate with min/recommended and note design-dependent splits + cross-repo endpoints. Mirror existing controller patterns in the primary repo.

---

## 8. Conventions & preferences (IMPORTANT)

- **NEVER delete or overwrite files without warning the user first** and spelling out what stays vs goes — even for "obvious" cleanup. (Standing user preference.)
- **Don't commit** — the user reviews and commits per repo themselves.
- Keep the **original BA source file** — it's the verbatim source of truth; your consolidated analysis is a paraphrased derivative, not a replacement. Don't treat it as a redundant copy.
- **Document other teams'/epics' resources factually** as dependencies; don't judge their applicability — track them in the dependency register.
- Schema preferences when proposing fixes: **Int PKs not BigInt; NOT NULL + backfill over nullable** (see CLAUDE.md / memory).
- CSV is a poor export here (loses colour-coding & multi-sheet structure) — prefer the xlsx.
- Convert relative dates to absolute in any written artifact.

---

## Appendix A — Workflow script skeleton

```js
export const meta = {
  name: 'epic-feasibility',
  description: 'Map <EPIC> requirements against the 5-repo SBE codebase; find undeliverable items + open questions',
  phases: [
    { title: 'Scan repos', detail: 'one agent per repo + schema deep-dive' },
    { title: 'Feasibility', detail: 'one agent per requirement cluster' },
    { title: 'Verify gaps', detail: 'adversarially re-check each non-Deliverable verdict' },
  ],
}
const REQ = '<path to a requirements brief .md you wrote>'
const ROOT = '/Users/uipl/Desktop/uipl/sbe/APIs'

const SCAN_SCHEMA = { /* repo, relevantModules[], relevantModels[{name,keyFields,purpose}],
  capabilities[{capability,status:present|partial|absent,evidence}], notes */ }
const FEAS_SCHEMA = { /* cluster, items[{reqId,reqTitle,subRequirement,
  verdict:Deliverable|Partial|NotDeliverable|NeedsClarification,
  reposImpacted[5 repos],gap,evidence,openQuestion}] */ }
const VERIFY_SCHEMA = { /* reqId,subRequirement,originalVerdict,
  confirmedVerdict,reasoning,evidence */ }

// Phase 1 — one agent per repo (+ schema deep-dive on admin-backend-api/prisma/schema.prisma)
phase('Scan repos')
const scans = (await parallel(REPOS.map(t => () =>
  agent(`Read ${REQ}. Scan ${ROOT}/${t.repo}. Focus: ${t.focus}. Return evidence-backed capability inventory.`,
    { label: `scan:${t.repo}`, phase: 'Scan repos', schema: SCAN_SCHEMA })))).filter(Boolean)
const digest = scans.map(s => /* compact text of models+capabilities */).join('\n\n')

// Phase 2 — one agent per requirement cluster, consuming the digest
phase('Feasibility')
const feas = (await parallel(CLUSTERS.map(c => () =>
  agent(`Judge cluster: ${c.desc}\nInventory:\n${digest}\nVerdict each atomic sub-req. Return structured.`,
    { label: `feas:${c.key}`, phase: 'Feasibility', schema: FEAS_SCHEMA })))).filter(Boolean)
const items = feas.flatMap(f => f.items)

// Phase 3 — adversarially verify every non-Deliverable item (try to prove the gap WRONG)
phase('Verify gaps')
const risky = items.filter(it => it.verdict !== 'Deliverable')
const verifications = (await parallel(risky.map(it => () =>
  agent(`Try to DISPROVE this gap. ${it.reqId}: ${it.subRequirement}. Claimed: ${it.verdict} — ${it.gap}.
    Search ${ROOT} (esp. admin-backend-api/prisma/schema.prisma). If it exists, downgrade & cite; else confirm.`,
    { label: `verify:${it.reqId}`, phase: 'Verify gaps', schema: VERIFY_SCHEMA })))).filter(Boolean)

return { scans, feasibilityItems: items, verifications }
```

Then in the main loop: apply verifications onto items, fold in referenced stories (Step 5), build the dependency register (Step 6), and generate the consolidated xlsx + summary md (Step 7) with openpyxl.

---

## Appendix B — Checklist

- [ ] Located requirement xlsx/pdf + referenced stories
- [ ] Decomposed into atomic sub-requirements
- [ ] Scanned all 5 repos; verified data claims against admin source-of-truth schema
- [ ] Verdict on every atomic item (4-value taxonomy)
- [ ] Adversarially verified every non-Deliverable item
- [ ] Folded in referenced stories (with page cites)
- [ ] Repo-impact computed (incl. not-impacted repos + primary repo)
- [ ] Cross-epic dependencies classified (Hard/Soft/Architectural)
- [ ] Open questions consolidated & prioritized
- [ ] Consolidated xlsx (7 sheets) + summary md in the epic folder
- [ ] Original BA source kept; nothing deleted without asking
