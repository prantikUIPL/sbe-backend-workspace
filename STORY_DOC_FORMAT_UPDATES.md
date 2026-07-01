# Story Doc Format (feasibility `.md` + `.xlsx`)

The spec for a story's feasibility docs (`.md` + `.xlsx`). The **canonical** format is
the one produced during **Phase 1 (Finalize scope with the human)** of
**[STORY_IMPLEMENTATION_PROCESS.md](STORY_IMPLEMENTATION_PROCESS.md)** — evolved from the
13.2 (Order Listing) session and finalized in the 13.3 (Order Details) scope session.
**13.3 is the reference example.**

> The `<Story> - Implementation Plan.md` is NOT part of this — it has its own schema
> (Plan File Schema v1.8.2) and is produced/owned by Phase 2 of the process doc.

---

## Verdict vocabulary

Every requirement carries exactly one verdict:

- **Deliverable** — confirmed buildable on existing code, no open dependency. (The plan
  is scoped to these only.)
- **Deferred** — buildable, but a decision has been postponed (e.g. an A-vs-B choice).
- **Blocked** — waiting on an identified owning story; **cite it** (story # + Jira key +
  sprint + assignee).
- **Not Deliverable** — no data *and* no owning story (parked open question).
- **Resolved** — a decision was made → the item becomes **Deliverable**; the decision is
  recorded in the **Requirements row** and the item is **dropped from Open Questions**.

Rule: **an item with no Open Questions entry is fully Deliverable.** (The legacy
`Partial` / `Out of Scope` verdicts usually reclassify into the above after Phase 1.)

---

## `.md` sections

`# Story X — Title`, `**Epic:**`, `**Confluence:**`, `**Build Status:**` (counts +
confirmed build scope), `## Summary`, `## Feasibility Counts`, `## Implementation Status`,
`## Requirements`, `## Endpoints`, `## Open Questions`, `## Cross-Epic Dependencies`,
`## Build Consolidation Notes`.

- **Feasibility Counts** table columns: `Deliverable | Deferred | Blocked | Not Deliverable | Partial | Out of Scope | Total`, followed by a one-line list of the confirmed build scope (the Deliverable req ids).
- **Open Questions** — the centralized action register: **one entry per non-Deliverable
  requirement** (see below). Resolved items are not kept here.
- **Implementation Status** — lifecycle-only (see below).

## `.xlsx` sheets

`Overview`, `Requirements`, `Endpoints`, `Open Questions`, `Cross-Epic Dependencies`,
`Implementation Status`.

### `Requirements` sheet
Columns: `Req ID | Requirement | Verdict | Build Focus | Delivered By | Reason (exists vs
to-build / gap) | Code Evidence | Dependency | Build Consolidation (reuse / delivered-by)
| Story Wording (verbatim, from Confluence) | Confluence | Impl Status (YYYY-MM-DD)`.
- The **Verdict** and **Dependency** cells carry the Phase-1 decision (Dependency = the
  blocking story + Jira key for Blocked items).
- **Resolved** decisions are recorded here (in Reason / Impl Status), **not** in Open Questions.

### `Open Questions` sheet — the centralized action register
**One row per non-Deliverable requirement.** Columns (8):
`Req | Item | Verdict | Open Question / What is needed | Dependency (blocking story +
Jira) | Assignee | Sprint / Jira status | Decision / Current direction`.
- **Styling:** workbook header style (bold white font on `1F4E78` fill, wrapped, row 1
  frozen at `A2`), data cells wrap-text + top-aligned, thin borders.
- **Verdict color-code** on the Verdict column: Not-Deliverable light red (`F8CBAD`),
  Blocked amber (`FFE699`), Deferred light blue (`DDEBF7`).
- **Resolved items are NOT here** — their decision lives in the Requirements row.

### `Implementation Status` sheet — lifecycle only
Two columns `Section | Detail` (bold header, col A ~48 / col B ~90, wrap). Rows:
`Status | Branch | SBE ticket | Commits | PR | Swagger tag | Build gates | Live smoke |
Confirmed build scope | Remaining | Not ready — see Open Questions | External
dependencies — see Cross-Epic Dependencies | Out of API scope`.
- It **points at** Open Questions (blockers/decisions) and Cross-Epic Dependencies
  (external producers) instead of duplicating them. For an unbuilt story it is mostly
  "Not started" + empty branch/PR placeholders; it fills in as you build (Phase 9).

### `Cross-Epic Dependencies` sheet
`Dependency | Needed For | Owner (story + Jira)` — external producers a story waits on.
Kept as its own sheet: it is the **dependency-angle** view, while Open Questions is the
**item-angle** view of the same blockers.

### `Overview` sheet
Metadata (Story ID / Title / Epic) + verdict counts (Deliverable / Deferred / Blocked /
Not Deliverable / Partial / Out of Scope / Total) + Build Status + Summary + lifecycle
fields (Implementation / Impl Branch / Impl Commits / PR).

### Reference openpyxl snippet (Open Questions register style + verdict color-code)

```python
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side

wb = openpyxl.load_workbook(XLSX)
ws = wb['Open Questions']                       # header + rows already written
HFILL = PatternFill('solid', fgColor='FF1F4E78'); HFONT = Font(bold=True, color='FFFFFFFF')
THIN = Side(style='thin', color='FFBFBFBF'); BORD = Border(THIN, THIN, THIN, THIN)
VFILL = {'Not Deliverable': 'FFF8CBAD', 'Blocked': 'FFFFE699', 'Deferred': 'FFDDEBF7'}
for c in range(1, ws.max_column + 1):
    h = ws.cell(1, c); h.font, h.fill, h.border = HFONT, HFILL, BORD
    h.alignment = Alignment(wrap_text=True, vertical='center', horizontal='center')
ws.freeze_panes = 'A2'
for r in range(2, ws.max_row + 1):
    for c in range(1, ws.max_column + 1):
        cell = ws.cell(r, c); cell.border = BORD
        cell.alignment = Alignment(wrap_text=True, vertical='top', horizontal='left')
    v = str(ws.cell(r, 3).value or '')          # color-code the Verdict cell
    for k, rgb in VFILL.items():
        if v.startswith(k): ws.cell(r, 3).fill = PatternFill('solid', fgColor=rgb)
wb.save(XLSX)
```

---

## Applying to another story

1. Do it as **Phase 1 (scope finalization)** of the process doc — per-item, with the human.
2. Map each requirement's status by **Req ID** (never by row position).
3. Open Questions = one row per non-Deliverable item; **Resolved** decisions go to the
   Requirements row (not Open Questions).
4. Recompute Feasibility Counts (incl. the **Deferred** column); slim Implementation Status
   to lifecycle-only; keep Cross-Epic Dependencies.
5. Commit in the workspace/docs repo with a descriptive scope, e.g.
   `docs(<epic>): rework <story> feasibility after per-item verdict review`. Stage **only**
   that story's files — don't let Google-Drive/Sheets sync churn in sibling stories ride along.
6. Do **not** touch that story's `- Implementation Plan.md`.
