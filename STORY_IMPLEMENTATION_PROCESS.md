# Story Implementation Process (replicable playbook)

A story-independent, repeatable process for taking **any** epic story from its
feasibility docs through to a shipped, reviewed feature branch — with a green CI
pipeline — and updated docs. Derived from the SBE-1146 / Story 13.2 (Order
Listing) **build** session, the Story 13.3 (Order Details) **scope-finalization**
session, and the SBE-1125 / Stories 24.1–24.4 (Order Management listing) **build +
CI-to-green** session; use it as the default workflow for other stories.

> Companion doc: **[STORY_DOC_FORMAT_UPDATES.md](STORY_DOC_FORMAT_UPDATES.md)** —
> the exact `.md`/`.xlsx` feasibility-doc format produced during Step 1 below
> (Open Questions register, slim Implementation Status, verdict vocabulary).

---

## Inputs (must exist before starting)

1. **Story feasibility docs** in the story folder: `<Story> .md` + `<Story> .xlsx`
   (requirements, verdicts, endpoints, open questions).
2. **Jira ticket id** for the story (e.g. `SBE-1234`).
3. A **preferred code-style reference** module (mirror its structure, but use the
   *target repo's* host conventions) — named in the plan produced by Step 3.

> The **implementation plan is NOT a pre-existing input** — it is produced,
> approved, and saved by **Step 3**, and only after scope is finalized with the
> human in **Step 1**.

---

## Phase 0 — Prerequisites / guardrails (carry these throughout)

- **The human drives every commit/push.** Steps 2, 6, and 9 are the three
  sanctioned commit gates in this process; even at those gates, commit/push on the
  human's go-ahead — never auto-commit outside them, and never push work the human
  hasn't seen.
- **Warn & confirm before any destructive op** (delete/overwrite); spell out what
  stays vs goes.
- **Scope finalization is human-in-the-loop and strictly per-item** (Step 1) — go
  **one requirement at a time**, do **not** batch, and do **not** assume the
  feasibility verdicts are already final.
- **Schema prefs:** `Int` PKs (not `BigInt`); prefer `NOT NULL` + backfill over
  nullable. `admin-backend-api` owns Prisma migrations; the other four use `db push`.
- **Commit conventions:** backend repos → `type(SBE-xxxx): description` (ticket id as
  the Conventional-Commits scope, taken from the branch name). Workspace/docs repo →
  descriptive scope (e.g. `docs(order-management): …`). **Omit** the Co-Authored-By
  and Claude-Session trailers.
- **Stay in scope** — touch only the module/story under work; never change unrelated
  modules to satisfy a lint/gate.
- **Verify claims independently** — re-run gates yourself; don't trust an agent's
  self-report. Report failures/skips honestly.

---

## Step 1 — Finalize each requirement's status with the human (one at a time) — HARD GATE

Using the feasibility docs, **review the requirements with the human one at a time**.
Do not move to the next requirement until the human has confirmed a status for the
current one. Walk **every open question** and **every requirement** — don't assume a
"Deliverable" verdict is already agreed.

For each item:

- **Verify against the actual code** (`grep`, `git blame`) — feasibility verdicts are
  often optimistic; re-derive them from what the code really supports.
- When the item **references or is owned by another story**, pull the **authoritative
  Jira/Confluence**: owning story **number + heading**, Jira key, **status, sprint,
  assignee**. Cite Confluence by **link + heading to search** (human-usable), never a
  bare page id.
- **"Code exists" ≠ "delivered"** — if the endpoint/feature already exists, confirm
  completion with the owning dev/ticket (it may be mid-sprint). Attribute authorship
  via `git blame`, not assumption.
- **Classify the verdict** (the human confirms it):
  - **Deliverable** — confirmed buildable on existing code, no open dependency.
  - **Deferred** — a decision the human has postponed (e.g. an A-vs-B choice).
  - **Blocked** — waiting on an identified story; **cite it** (story # + Jira + sprint + assignee).
  - **Not Deliverable** — no data *and* no owning story (parked open question).
  - **Resolved** — a decision was made; the item becomes **Deliverable**.
- **Resolved items:** record the decision in the **Requirements row** and **remove them
  from Open Questions**. Rule: *an item with no open question is fully Deliverable.*

**Gate:** do **not** proceed to Step 2 until the human has confirmed a status for
*every* requirement and open question.

## Step 2 — Update the docs, then commit & push to the workspace repo

Once the status for each requirement is set, **update the related feasibility docs**
(`.md` + `.xlsx`), following the companion
[STORY_DOC_FORMAT_UPDATES.md](STORY_DOC_FORMAT_UPDATES.md):

- Requirements **verdicts** (as confirmed in Step 1).
- The **Open Questions register** — one row per non-Deliverable item (question /
  blocking story + Jira / assignee / sprint / decision).
- Recompute the **Feasibility Counts**.
- Slim the **Implementation Status** to lifecycle-only; keep **Cross-Epic Dependencies**.
- Mind the Google-Drive/Sheets round-trip — don't commit sync-induced binary churn in
  sibling stories; stage only this story's files.

Then **commit and push the doc changes to the workspace repo** (descriptive `docs(...)`
scope, no AI trailers). This locks the agreed scope before any code is written.

## Step 3 — Plan the implementation, review with the human until approved

- Draft `<Story> - Implementation Plan.md` (**Plan File Schema v1.8.2**), scoped to the
  **confirmed Deliverable requirements only** — Deferred / Blocked / Not-Deliverable are
  explicitly excluded (they stay tracked in the Open Questions register).
- **Always use a modern, industry-standard approach.** When a current best-practice
  pattern, library, or API is relevant and you're unsure of the latest guidance,
  **search the web at that time** for an authoritative reference and cite it in the plan.
- Name a **code-style reference** module to mirror; **reuse existing modules/helpers**
  over new code.
- **Review the plan with the human and iterate until they explicitly approve it.**

## Step 4 — Save the approved plan into the story subfolder

Only after approval, **copy the approved plan into the relevant story subfolder** as
`<Story> - Implementation Plan.md`.

## Step 5 — Pick the branch, prep `dev`, then build + verify (workflow)

1. **Ask the human which branch to use** — a **new** branch or an **existing** one.
   - **New branch:** ask the human to confirm you should **update local `dev`** first,
     then cut `feature/SBE-1234-short-kebab-desc` off `dev`:
     ```sh
     bash /…/APIs/scripts/feature-branch-creator.sh "SBE-1234-short-kebab-desc"
     ```
   - **Existing branch:** ask the human to confirm you should **update `dev` and rebase
     the existing branch onto it** before building (resolve conflicts, keep local work).

   Do the branch/dev step **inline** (not inside a background workflow) so the state is
   confirmed before build.

2. **De-risk the substrate first (inline scouting):** repo builds on the expected Node;
   target Prisma models exist; DB reachable for a live smoke (note row counts); **trace
   the auth path** the smoke needs (header vs cookie, how it's signed, session/row
   requirements — the most common smoke blocker); confirm envelope/util/decorator/helper
   paths the plan references actually resolve.

3. **Use a workflow to write the code changes** per the approved plan. One workflow,
   sequential-ish phases:
   - **Implement** — follow the plan exactly: create the module files, honor every design
     decision + the public API contract + the deferred/out-of-scope list. Run **scoped**
     gates (`lint`, `typecheck`, `test -- <module>`) until green. **Do not commit.**
   - **Smoke + Review in parallel:**
     - **Live smoke** — seed data across the real scenarios (all types/states, a second
       tenant for isolation, an empty tenant), boot the server, authenticate, `curl` the
       endpoint, verify envelope/scoping/pagination/derivations, then **tear down** the
       seeded rows and report evidence + blockers honestly.
     - **Code review fan-out** — one agent per dimension: **correctness, security,
       conventions/style, plan+story conformance, test quality**; adversarially verify
       each finding (a skeptic per finding; reject false positives).
   - **Synthesize** a verdict (ship / ship-with-fixes / needs-work) with must/should/nit.

   If the workflow throws late (e.g. a structured-output retry cap on the final agent),
   **recover completed results from the run `journal.jsonl`** rather than re-running.

4. **Ensure the endpoint is exposed in Swagger** — a
   `SwaggerModule.createDocument({ include: [...] })` allowlist is **non-recursive**, so
   new modules must be added explicitly and their tag registered. Prove it empirically
   (generate the OpenAPI doc); don't assume.

5. **Independently verify + apply fixes:** re-run the gates yourself
   (`eslint`, `tsc --noEmit`, `jest <module>`); apply the **confirmed** review fixes.
   Where the code's choice is sound but diverges from the plan, **reconcile the plan doc**
   (don't add dead code); log it in the plan's revision log.

6. **Confirm everything marked Deliverable in the docs is actually delivered** — check
   each Deliverable requirement against the shipped code; nothing silently dropped, no
   out-of-scope/deferred work snuck in.

7. **Pre-push gate:** run the repo's pre-push script
   (`scripts/pre-push-check-<repo>.sh`):
   `npm ci → prisma generate → typecheck → lint:check → test:cov → build`. A regenerated
   Prisma client clears "stale client" failures in untouched files.

## Step 6 — Commit & push the code

Once everything is written and the gate is green, **commit and push** (when the human
gives the go-ahead): backend repo `feat(SBE-1234): …` (+ separate `fix(SBE-1234): …` for
follow-ups). No AI trailers. Personal feature branch → `--force-with-lease` is fine to
amend a bad subject.

## Step 7 — Human raises the PR; drive the pipeline to green (loop)

- **Ask the human to raise the PR on Bitbucket** (against `dev`).
- Once raised, **check the pipeline** (`scripts/check-pipelines.sh <repo> --branch <b>`)
  and confirm whether it finished **successfully**.
- **If it succeeded** — good, move on.
- **If it failed** — find out **which step** failed (Secret scan / Lint-typecheck-test /
  SonarQube gate; a later step shows `NOT_RUN` when an earlier one fails) via
  `check-pipelines.sh <repo> --logs <build#>`, and **prompt the human with suggested
  solutions.**
  - **If it failed on the SonarQube quality gate:** check the **new-code issues** on
    SonarQube (`scripts/check-sonar.sh <repo> --issues`), **verify each is ours**
    (author / `git blame` on file+line — never touch others' issues), **fix them locally**,
    update the code, and re-run the pre-push gate. SonarQube is **READ-ONLY** — never write
    to it.
- **Repeat this loop** — fix → commit & push → re-check pipeline — **until the pipeline
  succeeds.**

## Step 8 — Update the docs with the implementation status (NOT the plan file)

Once the pipeline succeeds, record implementation status in the story feasibility `.md`
**and** `.xlsx` (shipped vs remaining, open team decisions, cross-story dependencies,
branch / commits / PR / pipeline #). Follow
**[STORY_DOC_FORMAT_UPDATES.md](STORY_DOC_FORMAT_UPDATES.md)**. Leave the
`<Story> - Implementation Plan.md` untouched unless reconciling a plan/code divergence
(Step 5).

## Step 9 — Commit & push the doc changes to the workspace repo

**Commit and push** the updated feasibility docs to the workspace repo (descriptive
`docs(...)` scope, no AI trailers), staging only this story's files.

---

## Definition of done (per story)

- [ ] **Every requirement's status confirmed with the human, one at a time** (Step 1);
      Deliverable / Deferred / Blocked / Not-Deliverable / Resolved, with blocking
      stories cited.
- [ ] **Scope docs updated, committed & pushed** to the workspace repo (Step 2).
- [ ] **Implementation plan approved by the human**, using a modern industry-standard
      approach (Step 3), and **saved to the story subfolder** (Step 4), scoped
      **Deliverable-only**.
- [ ] Branch chosen with the human; `dev` updated (new) or updated + rebased (existing).
- [ ] Module implemented per plan via workflow; scoped gates green; **no**
      out-of-scope/deferred work.
- [ ] New route exposed in Swagger (if applicable), proven; live smoke passed (or gaps
      reported honestly), test data cleaned up; review findings verified & fixed; plan
      reconciled if needed.
- [ ] Everything marked Deliverable in the docs confirmed delivered.
- [ ] Full pre-push gate green; **code committed & pushed** (Step 6).
- [ ] **Human raised the PR**; pipeline driven to **SUCCESS** (SonarQube new-code issues
      fixed in-loop where applicable) (Step 7).
- [ ] Feasibility `.md` + `.xlsx` updated with Implementation Status (Step 8) and
      **committed & pushed** to the workspace repo (Step 9).
