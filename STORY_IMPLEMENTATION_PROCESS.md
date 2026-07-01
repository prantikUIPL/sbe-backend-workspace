# Story Implementation Process (replicable playbook)

A story-independent, repeatable process for taking **any** epic story from an
approved implementation plan through to a pushed, reviewed feature branch and
updated docs. Derived from the SBE-1146 / Story 13.2 (Order Listing) session; use
it as the default workflow for other stories.

> Companion doc: **[STORY_DOC_FORMAT_UPDATES.md](STORY_DOC_FORMAT_UPDATES.md)** —
> the doc-format additions to apply to a story's feasibility `.md`/`.xlsx`.

---

## Inputs (must exist before starting)

1. **Story feasibility docs** in the story folder: `<Story> .md` + `<Story> .xlsx`
   (requirements, verdicts, endpoints, open questions).
2. **Implementation plan** in the *same* story folder, named
   `<Story> - Implementation Plan.md`, following Plan File Schema v1.8.2.
3. **Jira ticket id** for the story (e.g. `SBE-1234`).
4. A **preferred code-style reference** module named in the plan (mirror its
   structure, but use the *target repo's* host conventions).

---

## Phase 0 — Prerequisites / guardrails (carry these throughout)

- **Never `git commit`/`push` without an explicit request** — the user reviews and
  commits per repo (unless they authorize otherwise for the session).
- **Warn & confirm before any destructive op** (delete/overwrite); spell out what
  stays vs goes.
- **Schema prefs:** `Int` PKs (not `BigInt`); prefer `NOT NULL` + backfill over
  nullable. `admin-backend-api` owns Prisma migrations; the other four use `db push`.
- **Commit conventions:** backend repos → `type(SBE-xxxx): description` (ticket id as
  the Conventional-Commits scope, taken from the branch name). Workspace/docs repo →
  descriptive scope (e.g. `docs(order-history): …`). **Omit** the Co-Authored-By and
  Claude-Session trailers.
- **Verify claims independently** — re-run gates yourself; don't trust an agent's
  self-report. Report failures/skips honestly.

---

## Phase 1 — Cut the feature branch (skill)

From **inside the target sub-repo** (its own git repo), run the feature-branch
skill. The script lives in the workspace `scripts/`, so call it by absolute path:

```sh
bash /…/APIs/scripts/feature-branch-creator.sh "SBE-1234-short-kebab-desc"
```

It syncs local `dev` to `origin/dev`, cuts `feature/SBE-1234-short-kebab-desc` off
`dev`, pushes, and sets upstream tracking. Relay its one-line confirmation. Do this
**inline** (not inside a background workflow) so the push is confirmed before build.

## Phase 2 — De-risk the substrate (inline scouting)

Before any heavy build, confirm the ground truth and remove the likely blockers:

- Repo builds / on the expected Node; target Prisma models exist in the repo's schema.
- **DB reachable** for a live smoke (psql via the repo's `DATABASE_URL`); note row
  counts so you know whether test data must be seeded.
- **Trace the auth path** the smoke will need — where the token comes from (header vs
  cookie), how it's signed, and any session/row requirements. This is the most common
  smoke blocker; solve it now (e.g. mint a token *and* insert the matching session row).
- Confirm the envelope/util/decorator/helper paths the plan references actually resolve.

## Phase 3 — Orchestrated build + verify (multi-agent workflow — opt-in)

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

## Phase 4 — Independently verify + apply fixes

- **Re-run the gates yourself** (`eslint`, `tsc --noEmit`, `jest <module>`).
- Apply the **confirmed** review fixes. Where the code's choice is sound but diverges
  from the plan, **reconcile the plan doc** to match (don't add dead code); log it in
  the plan's revision log.
- Check **cross-cutting integration** a per-file review can miss — e.g. is the new
  route actually exposed in Swagger? (A `SwaggerModule.createDocument({ include: [...] })`
  allowlist is non-recursive — new modules must be added explicitly.) Prove it
  empirically (generate the OpenAPI doc), don't assume.

## Phase 5 — Pre-push gate

Run the repo's pre-push script (per repo in `scripts/pre-push-check-<repo>.sh`):
`npm ci → prisma generate → typecheck → lint:check → test:cov → build`. Note that a
regenerated Prisma client (step 2) clears "stale client" typecheck/build failures in
untouched files, so a clean checkout passes end-to-end.

## Phase 6 — Commit & push (when asked)

- Backend repo: `feat(SBE-1234): …` (+ separate `fix(SBE-1234): …` for follow-ups like
  SonarQube findings). No AI trailers. Personal feature branch → `--force-with-lease`
  is fine to amend a bad subject.
- Push; a PR-create link / PR number comes back from the remote (open PR against `dev`).

## Phase 7 — Update the docs (NOT the plan file)

Record implementation status in the story feasibility `.md` **and** `.xlsx` (shipped
vs remaining, open team decisions, cross-story dependencies, branch/commits/PR). Follow
**[STORY_DOC_FORMAT_UPDATES.md](STORY_DOC_FORMAT_UPDATES.md)**. Leave the
`<Story> - Implementation Plan.md` untouched unless reconciling a plan/code divergence
(Phase 4).

---

## Definition of done (per story)

- [ ] Feature branch cut from `dev`, pushed, tracking origin.
- [ ] Module implemented per plan; scoped gates green; **no** out-of-scope/deferred work.
- [ ] Live smoke passed (or honestly reported gaps); test data cleaned up.
- [ ] Review findings verified; confirmed fixes applied; plan reconciled if needed.
- [ ] New route exposed in Swagger (if applicable), proven.
- [ ] Full pre-push gate green.
- [ ] Committed with ticket-scoped messages, no AI trailers; pushed; PR opened.
- [ ] Feasibility `.md` + `.xlsx` updated with Implementation Status.
