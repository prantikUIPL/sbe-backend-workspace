# Story Doc Format Updates (implementation-status additions)

During the SBE-1146 / Story 13.2 (Order Listing) session, the story's feasibility
docs (`.md` + `.xlsx`) were extended beyond the original per-story feasibility
format to track **implementation status** and **resolved/deferred decisions**. The
sibling stories (13.1, 13.3, and the Order Management stories) still use the
**baseline** format. This file is the spec for bringing any other story's docs up to
the **13.2 (extended)** format — apply it as stories move from *analysis* into
*implementation*.

> The `<Story> - Implementation Plan.md` is NOT part of this — it has its own schema
> (Plan File Schema v1.8.2) and is left as-is.

---

## Baseline format (13.1 / 13.3 / OM stories)

**`.md` sections:** `# Story X — Title`, `**Epic:**`, `**Confluence:**`,
`**Build Status:**`, `## Summary`, `## Feasibility Counts`, `## Requirements`,
`## Endpoints`, `## Open Questions`, `## Cross-Epic Dependencies`,
`## Build Consolidation Notes`.

**`.xlsx` sheets:** `Overview`, `Requirements`, `Endpoints`, `Open Questions`,
`Cross-Epic Dependencies`.
- `Requirements` columns (11): `Req ID, Requirement, Verdict, Build Focus, Delivered By, Reason (exists vs to-build / gap), Code Evidence, Dependency, Build Consolidation (reuse / delivered-by), Story Wording (verbatim, from Confluence), Confluence`.
- `Open Questions` columns (2): `#, Open Question`.

---

## Extended format (what 13.2 now has) — apply these deltas

### A. `.md` additions

1. **`**Implementation:**` line** — directly under `**Build Status:**`. One line:
   *N of M in-scope requirements shipped in `SBE-XXXX`; remaining item(s) + status.*
2. **`## Implementation Status (as of YYYY-MM-DD)` section** — placed just before
   `## Requirements`. Contains:
   - **Branch / commits / PR** line (branch name, commit SHAs, PR number, Swagger tag).
   - A **per-requirement status table**: `| Req | Status | Notes |` with
     ✅ Done / ⚠️ Partial / ⛔ Deferred / Out of Scope per requirement.
   - **Remaining in story** — numbered list of not-yet-built items + why (e.g. deferred
     pending a decision).
   - **Team decisions still open (no code until answered)** — bullets.
   - **Dependencies owned by other stories** — bullets (with owning story id).
   - A closing note on what is out of API scope (e.g. front-end wiring).
3. **Open Questions upgrade** — prefix each question with a status tag
   (`[RESOLVED YYYY-MM-DD]` / `[OPEN — for team discussion]` /
   `[OPEN — for team confirmation · WORK DEFERRED]`) and add a
   `- **Decision:**` / `- **Current direction (date):**` sub-bullet.
4. **`## Deferred Work` section** (only if the story defers a requirement) —
   what's deferred, why, and the decision that unblocks it.

### B. `.xlsx` additions

1. **`Requirements` sheet** — append one column: **`Impl Status (YYYY-MM-DD)`**
   (✅ Done (SBE-XXXX) / ⚠️ Partial / ⛔ DEFERRED / Out of Scope per row). Width ~46,
   wrap text, copy header style from the existing header cell.
2. **`Open Questions` sheet** — append two columns: **`Status`** and
   **`Resolution / Decision`**.
3. **New `Implementation Status` sheet** — two columns `Section | Detail` (bold header,
   col A ~30 / col B ~100, wrap). Rows: *Shipped (SBE-XXXX)*, *Remaining — <req>*,
   one *Open decision — …* row per open decision, one *Dependency — <story>* row per
   dependency, *Out of API scope*.
4. **`Overview` sheet** — append summary rows: `Implementation`, `Impl Branch`,
   `Impl Commits`, `PR`.

### Reference openpyxl snippet (append the Requirements column + new sheet)

```python
import openpyxl
from copy import copy
from openpyxl.styles import Font, Alignment

wb = openpyxl.load_workbook(XLSX)
ws = wb['Requirements']
col = ws.max_column + 1
src = ws.cell(1, 1)
h = ws.cell(1, col, 'Impl Status (YYYY-MM-DD)')
h.font, h.fill, h.alignment, h.border = copy(src.font), copy(src.fill), copy(src.alignment), copy(src.border)
for r in range(2, ws.max_row + 1):
    rid = str(ws.cell(r, 1).value).strip()          # map by Req ID, not row order
    ws.cell(r, col, STATUS[rid]).alignment = Alignment(wrap_text=True, vertical='top')
ws.column_dimensions[openpyxl.utils.get_column_letter(col)].width = 46

imp = wb.create_sheet('Implementation Status')       # Section | Detail
# … write rows, set widths 30 / 100, bold header …
wb.save(XLSX)
```

---

## Applying to another story

1. Confirm the story is entering implementation (has a shipped/partial build).
2. Apply the `.md` additions (A) and `.xlsx` additions (B), mapping each requirement's
   status by **Req ID** (never by row position).
3. Keep `Impl Status` wording consistent: `✅ Done (SBE-XXXX)` /
   `⚠️ Partial (SBE-XXXX) — <what's partial>` / `⛔ DEFERRED — <blocker>` /
   `Out of Scope — <owner>`.
4. Commit in the workspace/docs repo with a descriptive scope, e.g.
   `docs(<epic>): record <story> implementation status`.
5. Do **not** touch that story's `- Implementation Plan.md`.
