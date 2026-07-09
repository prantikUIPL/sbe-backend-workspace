# Email & SMS Combined Release — Development Effort Estimate

**Covers:** the full end-to-end execution of the combined release — Scheduling engine (76.6/77.8) + Dynamic Recipient Resolution / DRR (77.9) + SMS Provider Integration (76.8) — as one release on the shared spine.
**Date:** 2026-07-09
**Two versions:** engineering effort **without AI assistance** and **with AI assistance**.

---

## 0. What this is (and what it is not)

- These are **backend-engineering build-effort hours** (design-to-merge dev work), NOT elapsed calendar time to launch. See §5 — the launch date is governed by external long poles AI cannot compress.
- **DRR (122.0h)** and **SMS (73.0h)** are the plans' own documented, table-summed totals. The **scheduling engine (~190h)** carries **no formal estimate in its plan**, so §4 builds one phase-by-phase. The cross-cutting lines (D2, integration/QA, absorption) are estimates.
- The **AI-assistance model is per-category, not a flat multiplier** (§3). Confidence and assumptions are in §6.

### These hours are backend-dev only — NOT a fully-loaded delivery cost

**IN the number:** backend coding on the 5 NestJS services; developer-written unit/integration tests + conformance vectors; cross-repo integration; multi-PR coordination buffer; staging gate-proof verification.

**NOT in the number (uncounted, must be added for a full delivery estimate):**

| Excluded bucket | Rough magnitude | Note |
|---|---|---|
| **Front-end / admin-UI development** | **~100–200h (unscoped)** | These are *backend API* plans. Schedule builder, recipient-token editor, preview UI, SMS template management all live in the separate admin front-end and are entirely uncounted. **Largest omission.** |
| **Dedicated QA** | **+25–35% of dev** | Manual test plans, regression of the **14 live email flows**, UAT, bug-fix churn from QA findings |
| **Peer code review** (reviewer-side) | **+~10%** | Author-side rebase/integration is in the buffers; reviewer hours are not |
| **BA / analysis** | separate role | Reconciling the ~44 open questions, producing the DRR-04 matrix |
| **Project management / release coordination** | separate role | Standups, "merges-done" tracking, sprint overhead |
| **DevOps / provisioning** | see §5 | Twilio account, 10DLC paperwork, AWS Secrets, deploys |
| **Legal** | see §5 | SMS consent policy |

**Fully-loaded engineering (backend + front-end + QA + review) is therefore roughly ~1.7–2.2× the backend-only figure** — i.e. the ~440h backend could be ~750–950h all-in without AI — pending a front-end scope, the largest unknown.

---

## 1. Bottom line

| | **Without AI** | **With AI** |
|---|---|---|
| **Total engineering effort** | **≈ 440 hours** | **≈ 305 hours** |
| In dev-days (8h) | ≈ 55 days | ≈ 38 days |
| Active-dev calendar — 2–3 devs in parallel | ≈ 7–9 weeks | ≈ 4.5–6 weeks |
| Active-dev calendar — solo | ≈ 11 weeks | ≈ 7.5 weeks |

AI compresses the **build effort by ~31%**. It does **not** compress the launch date (§5).

---

## 1A. Aggressive floor — the minimum build hours, pushed hard

The §1 "With AI" figure (≈305h) is a *realistic* plan number, not a floor. If the goal is the **absolute minimum backend build hours** — max AI leverage, buffers cut, integration/QA reduced to bare-minimum staging gate-proofs, absorption at its low end, strong devs already fluent in this codebase, and clean execution with **no rework** — the floor is **≈ 250 hours (with AI)**.

| Scenario | Backend-only hours |
|---|---|
| Without AI, normal estimate | ≈ 438h |
| Without AI, aggressive | ≈ 375h |
| With AI, normal estimate | ≈ 304h |
| **With AI, aggressive floor** | **≈ 250h** |

The floor stacks two reductions — AI leverage *plus* trimming. Only AI compresses the greenfield/test-scaffolding bulk, which is why the with-AI floor drops much further than the without-AI one.

**Aggressive per-line (the "With AI" column trimmed):**

| Line | With AI (normal) | Aggressive floor |
|---|---|---|
| Scheduling engine | 134h | ~115h |
| DRR | 88h | ~76h |
| SMS | 45h | ~38h |
| D2 schema fix | 7h | ~5h |
| Release integration / staging proofs | 19h | ~12h |
| Absorption (TBD) | 11h | ~8h (or defer) |
| **Total** | **304h** | **≈ 250h** |

**~110–120h of that floor is non-compressible.** Aggressive trimming works on the greenfield code, DTOs, seeders, admin CRUD, test scaffolding, and the D2 mechanical edits. It must **not** touch: shared-prod-DB migration safety (~15–20h, human-review-bound), the scheduling executor's concurrency correctness (~40h), the DRR engine core (~30h), or the staging gate-proofs for the SKIP-gate / live-send flips (~12h). Cutting those does not save time — it relocates the cost to a production incident.

**The floor does not move the launch date (§5).** Even at 250h the release still waits on the three external clocks — 10DLC/Twilio registration, the BA's DRR-04 trigger→token matrix, and legal sign-off on SMS consent. Aggressive compression finishes the *code* ~3–4 weeks sooner; it does **not** ship the *release* sooner. The highest-leverage time-reduction move is starting 10DLC + the BA matrix + legal on **day one (MS0)** — not trimming dev hours.

---

## 2. Breakdown by track

| Track | Without AI | With AI | Basis |
|---|---|---|---|
| **Scheduling engine** (76.6/77.8) | 190h | 134h | **estimated** — §4 phase table |
| **DRR** (77.9) | 122h | ~88h | plan documented total; AI factor applied |
| **SMS** (76.8) | 73h | ~45h | plan documented total; AI factor applied |
| **D2 schema fix** (5 schemas + ~23 call sites, standalone PR) | 14h | 7h | estimated (mostly mechanical) |
| **Release integration / QA / staging gate proofs** | 24h | 19h | estimated (review-bound) |
| **Absorption** of already-built timers (24.15 payment-reminder cron, cart-expiry) | 15h | 11h | estimated, **TBD until re-audit** |
| **Total** | **≈ 438h** | **≈ 304h** | |

**Note on no double-counting:** the unified `NotificationLog` migration is already inside DRR's 122h (its Step 1); the SMS gate-flip is inside SMS's 73h (its H1); DRR reuses the scheduler's resolver substrate rather than rebuilding it. The three track totals are additive without overlap. D2, release-integration and absorption are genuinely *outside* all three plan tables.

---

## 3. The AI-assistance model (per category)

AI leverage is not uniform. Factors applied (`with-AI = without-AI × factor`):

| Work category | Factor | Rationale |
|---|---|---|
| **Greenfield code** (SmsService, resolver registry, DTOs, seeders, utils) | **×0.55** (~45% faster) | Spec-to-code translation and boilerplate — AI's strongest case; design is already fully written |
| **Stateful / concurrency logic** (materializer, dispatcher, `SKIP LOCKED` claim, reaper, DST, catch-up, DRR engine core) | **×0.75** (~25% faster) | AI drafts fast but correctness is subtle; review/test burden stays (and should) |
| **Migrations on the shared prod DB** | **×0.85** (~15% faster) | Five services read one DB; safety verification is human-review-bound, not draft-bound |
| **Admin CRUD / validators** | **×0.55** | Greenfield, pattern-heavy |
| **Tests / conformance vectors** | **×0.50** (~50% faster) | AI excels at test scaffolding; still needs review |
| **Integration / QA / staging proofs** | **×0.80** | Coordination and verification, modest compression |
| **Mechanical edits** (D2 ~23 call sites) | **×0.50** | Repetitive, well-specified |
| **Process / external** (client question packs, R&D, PR coordination) | **×0.90–1.00** | Human coordination barely compresses; external work not at all |

---

## 4. Scheduling engine — phase-by-phase estimate (the table it was missing)

Built from the approved scheduling plan (Revision 3) structure + the fixes addendum. Per-phase AI factor blended from §3 by the phase's work mix.

| Phase | Scope | Without AI | With AI |
|---|---|---|---|
| **0** | Substrate verify + worker-schema mirror prerequisite | 3h | 2.5h |
| **1** | Schema + flags (`notification_schedules`, `notification_schedule_occurrences`, enums, `is_schedulable`, `supports_scheduling`), 5-repo mirror, backfill + seeder | 18h | 15h |
| **2** | Admin config CRUD + per-kind DTO validation matrix (ANCHOR_RELATIVE / FOLLOW_UP / RECURRING, timezone, offsets, recurrence, stop-condition) + SQS hot-reload | 26h | 15h |
| **3** | Executor: heartbeat cron + re-entrancy guard, materializer (look-ahead window, roll-forward, series anchor, stable `dedupe_key`/`offset_key`, PENDING recompute), dispatcher, `FOR UPDATE SKIP LOCKED` claim, retry/backoff `[5m,30m,2h]` + `SENDING` reaper, DST-correct wall-clock, catch-up sweep | 56h | 42h |
| **4** | Three kinds complete + recipient/replacements-from-anchor (`recipient_source`/`replacements_map`, restricted resolver), FOLLOW_UP two capture modes, RECURRING "until answered" per-instance, stop-condition resolvers, re-materialization on rule edit | 32h | 24h |
| **Tests** | Worker executor suite (materialize/dispatch/retry/DST/catch-up) + admin config suite | 24h | 12h |
| **Addendum** | Hardening S1–S7 / X1–X2: S1 retention cron + FOLLOW_UP guard, S2 claim, S3 catch-up policy + per-skip/aggregate alerts, S5 DST fall-back test, S6 tz fail-closed + ingest IANA validation, X1 enum without `CART_CONVERTED`, X2 three verification tests | 25h | 17.5h |
| **Buffer** | Multi-PR coordination across 5 repos | 6h | 5.4h |
| | **Total** | **190h** | **≈ 134h** |

---

## 5. The launch caveat (unchanged by AI)

These hours are **build effort**, not elapsed time to go live. Three external gates AI does not touch set the actual launch date:

- **10DLC + Twilio registration** — days-to-weeks of carrier waiting; can be the release date on its own. Start day one (MS0).
- **BA/client answers** to the open questions (the DRR-04 trigger→token matrix especially) — hard-gate the `DRR_LIVE_SEND_ENABLED` flip.
- **Legal sign-off** on the SMS consent policy — hard-gate on US go-live.

**The real effect of AI here** is not a shorter launch date — it is that the **code finishes well before the external clocks do** (~4.5–6 weeks vs ~7–9), moving the bottleneck fully onto the 10DLC/BA/legal calendar. That is why starting those on day one matters more than dev speed.

---

## 6. Confidence & assumptions

- **Firm:** DRR (122h) and SMS (73h) — documented, table-summed in their plans.
- **±20% estimate:** the scheduling engine (~190h) and the cross-cutting lines. If a commit-grade number is needed, have a second engineer sanity-check the §4 table — it is the largest single line and the one without a plan-authored figure.
- **TBD:** absorption (15h) is a placeholder until the merges-done re-audit produces the actual absorption inventory (24.15 payment-reminder cron, cart-expiry, anything else landing before build). It could grow.
- **AI factors** are a reasoned model, not measured throughput on this codebase; real leverage varies by developer and by how much of the design is nailed down (here, a lot — which favors AI).
- **Excludes:** the earlier template-CRUD phase (already shipped, SBE-671); ongoing production support; and all external/calendar items in §5 (which are not engineering hours).
- **Parallelism assumption** for the calendar rows: the build order (MS0–MS9) is designed for concurrency — SMS dark-build runs alongside DRR, D2 lands early, BA sessions run alongside everything. Solo figures assume strictly sequential work.

---

*Per project convention: no commits are made by this document or its pipeline; the user reviews and commits everything. The approved scheduling plan, both stories' registers, and the frozen known-issues registers remain unedited.*
