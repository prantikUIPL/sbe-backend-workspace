# Story Implementation Process (replicable playbook)

A story-independent, repeatable process for taking **any** epic story from its
feasibility docs through to a pushed, reviewed feature branch and updated docs.
Derived from the SBE-1146 / Story 13.2 (Order Listing) **build** session and the
Story 13.3 (Order Details) **scope-finalization** session; use it as the default
workflow for other stories.

> Companion doc: **[STORY_DOC_FORMAT_UPDATES.md](STORY_DOC_FORMAT_UPDATES.md)** —
> the exact `.md`/`.xlsx` feasibility-doc format produced during Phase 1 below
> (Open Questions register, slim Implementation Status, verdict vocabulary).

---

## Inputs (must exist before starting)

1. **Story feasibility docs** in the story folder: `<Story> .md` + `<Story> .xlsx`
   (requirements, verdicts, endpoints, open questions).
2. **Jira ticket id** for the story (e.g. `SBE-1234`).
3. A **preferred code-style reference** module (mirror its structure, but use the
   *target repo's* host conventions) — named in the plan produced by Phase 2.

> The **implementation plan is NOT a pre-existing input** — it is produced, approved,
> and saved by **Phase 2**, and only after scope is finalized with the human in **Phase 1**.

---

## Phase 0 — Prerequisites / guardrails (carry these throughout)

- **Never `git commit`/`push` without an explicit request** — the user reviews and
  commits per repo (unless they authorize otherwise for the session).
- **Warn & confirm before any destructive op** (delete/overwrite); spell out what
  stays vs goes.
- **Scope finalization is human-in-the-loop and per-item** (Phase 1) — go one-by-one,
  do **not** batch, and do **not** assume the feasibility verdicts are already final.
- **Schema prefs:** `Int` PKs (not `BigInt`); prefer `NOT NULL` + backfill over
  nullable. `admin-backend-api` owns Prisma migrations; the other four use `db push`.
- **Commit conventions:** backend repos → `type(SBE-xxxx): description` (ticket id as
  the Conventional-Commits scope, taken from the branch name). Workspace/docs repo →
  descriptive scope (e.g. `docs(order-history): …`). **Omit** the Co-Authored-By and
  Claude-Session trailers.
- **Verify claims independently** — re-run gates yourself; don't trust an agent's
  self-report. Report failures/skips honestly.

---

## Phase 1 — Finalize scope with the human (requirements + open questions) — HARD GATE

Before any plan, settle exactly what will be built. Walk **every open question** and
**every requirement whose verdict is not "Deliverable"** — one-by-one, with the human.

For each item:

- **Verify against the actual code** (`grep`, `git blame`) — feasibility verdicts are
  often optimistic; re-derive them from what the code really supports.
- When the item **references or is owned by another story**, pull the **authoritative
  Jira/Confluence**: owning story **number + heading**, Jira key, **status, sprint,
  assignee**. Cite Confluence by **link + heading to search** (human-usable), never a
  bare page id.
- **"Code exists" ≠ "delivered"** — if the endpoint/feature already exists, confirm
  completion with the owning dev/ticket (it may be mid-sprint). Attribute authorship via
  `git blame`, not assumption.
- **Classify the verdict:**
  - **Deliverable** — confirmed buildable on existing code, no open dependency.
  - **Deferred** — a decision the human has postponed (e.g. an A-vs-B choice).
  - **Blocked** — waiting on an identified story; **cite it** (story # + Jira + sprint + assignee).
  - **Not Deliverable** — no data *and* no owning story (parked open question).
  - **Resolved** — a decision was made; the item becomes **Deliverable**.
- **Resolved items:** record the decision in the **Requirements row** and **remove them
  from Open Questions**. Rule: *an item with no open question is fully Deliverable.*

**Update the feasibility docs as you go** (`.md` + `.xlsx`), following the companion
[STORY_DOC_FORMAT_UPDATES.md](STORY_DOC_FORMAT_UPDATES.md):

- Requirements **verdicts**.
- The **Open Questions register** — one row per non-Deliverable item (question / blocking
  story + Jira / assignee / sprint / decision).
- Recompute the **Feasibility Counts**.
- Slim the **Implementation Status** to lifecycle-only; keep **Cross-Epic Dependencies**.
- Batch the `.xlsx` sync; mind the Google-Drive/Sheets round-trip — don't commit
  sync-induced binary churn in sibling stories.

**Gate:** do **not** proceed to Phase 2 until *every* open question and non-Deliverable
item is finalized with the human.

## Phase 2 — Draft, approve, and save the implementation plan

- Draft `<Story> - Implementation Plan.md` (**Plan File Schema v1.8.2**), scoped to the
  **confirmed Deliverable requirements only** — Deferred / Blocked / Not-Deliverable are
  explicitly excluded (they stay tracked in the Open Questions register).
- Name a **code-style reference** module to mirror; **reuse existing modules/helpers**
  over new code.
- Get **explicit human approval** of the plan. **Only after approval, save it into the
  story folder** as `<Story> - Implementation Plan.md`.

## Phase 3 — Cut the feature branch (skill)

From **inside the target sub-repo** (its own git repo), run the feature-branch
skill. The script lives in the workspace `scripts/`, so call it by absolute path:

```sh
bash /…/APIs/scripts/feature-branch-creator.sh "SBE-1234-short-kebab-desc"
```

It syncs local `dev` to `origin/dev`, cuts `feature/SBE-1234-short-kebab-desc` off
`dev`, pushes, and sets upstream tracking. Relay its one-line confirmation. Do this
**inline** (not inside a background workflow) so the push is confirmed before build.

## Phase 4 — De-risk the substrate (inline scouting)

Before any heavy build, confirm the ground truth and remove the likely blockers:

- Repo builds / on the expected Node; target Prisma models exist in the repo's schema.
- **DB reachable** for a live smoke (psql via the repo's `DATABASE_URL`); note row
  counts so you know whether test data must be seeded.
- **Trace the auth path** the smoke will need — where the token comes from (header vs
  cookie), how it's signed, and any session/row requirements. This is the most common
  smoke blocker; solve it now (e.g. mint a token *and* insert the matching session row).
- Confirm the envelope/util/decorator/helper paths the plan references actually resolve.

## Phase 5 — Orchestrated build + verify (multi-agent workflow — opt-in)

Only when multi-agent orchestration is requested. One workflow, sequential-ish phases:

1. **Implement** (1 agent) — follow the plan exactly: create the module files, honor
   every design decision + the public API contract + the deferred/out-of-scope list.
   Run **scoped** gates (`lint`, `typecheck`, `test -- <module>`) until green. **Do not
   commit.**
2. **Smoke + Review in parallel:**
   - **Live smoke** (1 agent) — seed data across the real scenarios (all types/states,
     a second tenant for isolation, an empty tenant), boot the server, authenticate,
     `curl` the endpoint, verify envelope/scoping/pagination/derivations, then **tear
     down** the seeded rows and report evidence + blockers honestly.
   - **Code review fan-out** — one agent per dimension: **correctness, security,
     conventions/style, plan+story conformance, test quality**.
3. **Adversarially verify** each finding (a skeptic per finding; reject false positives).
4. **Synthesize** a verdict (ship / ship-with-fixes / needs-work) with must/should/nit.

If the workflow throws late (e.g. a structured-output retry cap on the final agent),
**recover completed results from the run `journal.jsonl`** rather than re-running.

## Phase 6 — Independently verify + apply fixes

- **Re-run the gates yourself** (`eslint`, `tsc --noEmit`, `jest <module>`).
- Apply the **confirmed** review fixes. Where the code's choice is sound but diverges
  from the plan, **reconcile the plan doc** to match (don't add dead code); log it in
  the plan's revision log.
- Check **cross-cutting integration** a per-file review can miss — e.g. is the new
  route actually exposed in Swagger? (A `SwaggerModule.createDocument({ include: [...] })`
  allowlist is non-recursive — new modules must be added explicitly.) Prove it
  empirically (generate the OpenAPI doc), don't assume.

## Phase 7 — Pre-push gate

Run the repo's pre-push script (per repo in `scripts/pre-push-check-<repo>.sh`):
`npm ci → prisma generate → typecheck → lint:check → test:cov → build`. Note that a
regenerated Prisma client (step 2) clears "stale client" typecheck/build failures in
untouched files, so a clean checkout passes end-to-end.

## Phase 8 — Commit & push (when asked)

- Backend repo: `feat(SBE-1234): …` (+ separate `fix(SBE-1234): …` for follow-ups like
  SonarQube findings). No AI trailers. Personal feature branch → `--force-with-lease`
  is fine to amend a bad subject.
- Push; a PR-create link / PR number comes back from the remote (open PR against `dev`).

## Phase 9 — Update the docs (NOT the plan file)

Record implementation status in the story feasibility `.md` **and** `.xlsx` (shipped
vs remaining, open team decisions, cross-story dependencies, branch/commits/PR). Follow
**[STORY_DOC_FORMAT_UPDATES.md](STORY_DOC_FORMAT_UPDATES.md)**. Leave the
`<Story> - Implementation Plan.md` untouched unless reconciling a plan/code divergence
(Phase 6).

---

## Definition of done (per story)

- [ ] **Scope finalized with the human** — every open question + non-Deliverable item
      decided (Deliverable / Deferred / Blocked / Not-Deliverable / Resolved), with
      blocking stories cited; feasibility `.md` + `.xlsx` updated.
- [ ] **Implementation plan approved by the human and saved** to the story folder,
      scoped **Deliverable-only**.
- [ ] Feature branch cut from `dev`, pushed, tracking origin.
- [ ] Module implemented per plan; scoped gates green; **no** out-of-scope/deferred work.
- [ ] Live smoke passed (or honestly reported gaps); test data cleaned up.
- [ ] Review findings verified; confirmed fixes applied; plan reconciled if needed.
- [ ] New route exposed in Swagger (if applicable), proven.
- [ ] Full pre-push gate green.
- [ ] Committed with ticket-scoped messages, no AI trailers; pushed; PR opened.
- [ ] Feasibility `.md` + `.xlsx` updated with Implementation Status.
