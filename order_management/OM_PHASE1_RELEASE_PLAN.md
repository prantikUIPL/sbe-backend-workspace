---
atom_id: OM-P1
title: Order Management Phase-1 Release (7 stories, ship-together)
version: v1
status: approved
approved_by: Prantik Saha
approved_at: 2026-07-03
type: implementation
sessions: 7
session: 1
epic: "Order Management (SBE-1078)"
risk_tier: high
priority: Must Have
depends_on: [SBE-1125 (24.1-24.4, shipped), SBE-1138 (24.14, shipped), SBE-1129 (24.5, shipped 2026-07-03)]
blocks: []
covers_atoms: [SBE-1133, SBE-1134, SBE-1135, SBE-1132, SBE-1131, SBE-1130, SBE-1139]
tags: [order-management, refunds, cancellation, payment-plan, reminders, ship-together]
plan_family: OM-P1
author: Prantik Saha (gate + plan sessions with Claude)
tracker_ref: https://unifiedinfotech.atlassian.net/browse/SBE-1078
regulated_workload: false
---

# OM-P1 Implementation Plan — Order Management Phase-1 Release (v1 — Approved)

**Revision log:** v1 draft 2026-07-03 → approved by Prantik Saha 2026-07-03 (no content changes requested at review).

**Scope:** 7 build phases on ONE branch, one release, + a Phase 8 delivery audit at close-out. Phase 1: 24.9 Refunds (SBE-1133) · Phase 2: 24.10 Cancellation (SBE-1134) · Phase 3: 24.11 Cancel/Refund Emails (SBE-1135) · Phase 4: 24.8 Payment Plans (SBE-1132) · Phase 5: 24.7 Payments View (SBE-1131) · Phase 6: 24.6 Order Details (SBE-1130) · Phase 7: 24.15 Payment Reminders (SBE-1139) · Phase 8: Delivery Audit (deliverable-in → delivered-out reconciliation).

**Source:** the seven gate-locked feasibility docs (commits d2d4b98, 156b9e5, c230730, 17578f3, f0d9864, fce7b74, a782d37) + `OM_PHASE1_SHARED_UNIT_LEDGER.md` (U1–U20 + rules 1–7). The story docs are the per-requirement spec; the ledger is the ownership contract; this plan is the build sequence. Where this plan and a story doc disagree, the story doc wins and this plan gets amended.

**Branch decision (locked with Prantik 2026-07-03):** all changes on the existing **`feature/SBE-1125`** branch in each of the 5 repos — verified 0 ahead of origin/dev everywhere (fully merged history), so kickoff is a pure fast-forward. Commits carry per-story scopes (`type(SBE-1133):` … `type(SBE-1139):`), precedent: 24.5's `feat(SBE-1129):` commits on this same branch. **Prantik reviews and commits all code, per repo** — the agent stages nothing without go-ahead.

---

## Gate Contract (release-level acceptance)

- **Every requirement in the Coverage Matrix (Appendix A) is delivered by its named phase/step.** A Deliverable req with no green step = release not done.
- Pre-push gates GREEN in all 5 repos: gitleaks → lint/typecheck/test → SonarQube quality gate (incl. **duplication** — ledger rule 4).
- All migrations: clean `migrate dev` on a fresh DB + seeders re-run idempotently; other 4 repos `db push` mirrors match admin schema.
- Live smoke of the new route surface (checklist in Phase-6/7 steps) against a locally booted stack.
- Nothing delivered from the exclusion list (Deferred section) — verified by route/schema diff.

Each phase additionally closes on its own binary gate (per-phase Gate lines below).

---

## Context

**Why:** 13 of 15 Order Management stories are gated or shipped; these 7 are scope-locked and ship as one release. Without this release: no refunds (dashboard-only today), no admin cancellation, no manual-payment lifecycle (check/wire rows can't be recorded as paid), no order detail page, no payment reminders. Blocked downstream: 24.13 (reuses U5), the E&S scheduling system's payment-due absorption (OQ-4 hand-off), FE order-management screens.

**What:** The admin order-lifecycle backend: a per-installment refund primitive + ledger (U1–U3), transactional cancel with PT cascade + inventory release (U4–U5), cancel/refund emails (U6), the manual-payment column set + C13 mapper + Mark-as-Paid PATCH (U7–U12), the payments read view (U13), the order-detail aggregate + edits + void (U14–U18), and the reminder cron (U19) — across admin-backend-api (primary), external-api-service (webhook + Stripe wrapper), background-worker-service (crons), exhibitor/pulse (schema mirrors + writer updates).

### Reference Documents

| Document | Type | Refer To | Purpose |
|----------|------|----------|---------|
| `OM_PHASE1_SHARED_UNIT_LEDGER.md` | Ownership contract | Full file | U1–U20 allocations, rules 1–7, sequencing skeleton |
| `24.9 - Refund Management.md` | Story spec | Requirements + Decisions | Refund primitive/composition semantics, D1–D3, refund_failed |
| `24.10 - Order Cancellation.md` | Story spec | Requirements + 24.10-k row | Cancel flow, cascade shape, releaseForOrder spec |
| `24.11 - Order Cancellation Email Notification.md` | Story spec | Requirements + D1–D3 | Slugs, one-email-per-action, recipient chain, post-commit dispatch |
| `24.8 - Payment Plan Management.md` | Story spec | Requirements + D1–D4 | payment_type/payment_memo migration, cron guards, mapper, PATCH semantics, locks |
| `24.7 - Manual Payment Methods.md` | Story spec | 24.7-e row | GET payments route composition |
| `24.6 - Order Details.md` | Story spec | Requirements + D1–D7/D-z + OQ register | Aggregate fields, derivations, void endpoint, edit matrix |
| `24.15 - Payment Reminder Notifications.md` | Story spec | Requirements + D1–D5 | Cron predicates, settings family + provenance-comment directive, templates |
| Payment Milestone Statuses sheet | Business spec | Status Breakdowns tab | Label map, per-row actions, edit-rules source (URL in 24.6 doc header) |
| exhibitor `order-details.service.ts` / `order-details.helpers.ts` | Behavioral spec (NOT source to copy) | coupon join :39/:163; classifyOrderItems :104 | Semantics for 24.6 aggregate — implement natively (rule 4) |
| exhibitor `orders.helpers.ts` | Behavioral spec | deriveIsOverdue :74-79, settled set :31 | 24.15 predicate + 24.7 label semantics |
| worker `payment-charge-scheduler.registrar.ts` / `.task.ts` / `.service.ts` | Pattern reference | :63-84 / :22-65 / :60-82 | Registrar/task/cron structure for Phase 7 |
| admin `order-actions.service.ts` | Pattern reference | :697/:993 sendFromTemplate discipline | Route home + non-throwing mail pattern (Phases 3/6) |
| admin `base-agreement-document.service.ts` (adeba9f) | Pattern reference | Full commit | The hoist-to-shared-base precedent for any same-repo reuse |

**Dependencies (all complete):** 24.1–24.4 (orders module, list, helpers, permission seeder block), 24.14 (notes columns + PATCH), 24.5 (agreement/invoice/portal actions — live on dev 2026-07-03). No blocking dependencies.

**Scope boundary:** this release builds ONLY inside our modules: admin `src/admin/orders/**` + migrations/seeders, external-api webhook + a Stripe refund wrapper, worker scheduler/jobs/notification, exhibitor/pulse schema mirrors + the 5 PT-writer field additions (U7). Cart-module gaps = register rows (24.6 OQ-1), NOT code here. Parked/deferred items in Deferred section are absent by design.

---

## Design Decisions

All design decisions were made and locked at the 2026-07-03 gates and live in the story docs' Decisions sections — they are BINDING here; this plan does not reopen them. Index:

| ID here | Source | One-line binding effect |
|---|---|---|
| P-D1 | 24.9 D1/D2/D3 | Refund = per-installment primitive + order-level composition; `refund_failed` enum value; amount-aware `charge.refunded`; `paid_amount` stays gross |
| P-D2 | 24.10 D1/D2 + k | Cancel composes 24.9's service; cascade = widened where + `next_retry_at:null`; `releaseForOrder` in the cancel tx |
| P-D3 | 24.11 D1–D3 | Slugs `order_canceled`/`order_refunded`; one-email-per-action; billing_email → contact → skip+log; post-commit dispatch |
| P-D4 | 24.8 D1–D4 | `payment_type` (CartPaymentMethod, backfill credit_card NOT NULL, doc-comments), `payment_memo` nullable, stripe cols nullable + why-comments, cron guards, `admin_manual` source, Mark-as-Paid/Unpaid semantics, plan locks |
| P-D5 | 24.7 D3 | NO order-level payment-status PATCH — read route only |
| P-D6 | 24.6 D1–D7, D-z | Derived `status_display` (no enum migration); derivation chain for rep/source; additional_emails Json; per-installment void owned here; register-not-fix for cart gaps |
| P-D7 | 24.15 D1–D5 | Email-only; settings family 7/7/14 pending BA **with gate-provenance doc-comments (user directive)**; independent cron; self-seeded slugs; manual-rows-only predicates |
| P-D8 | Ledger rule 4 (user directive) | NO copy/import/replication: same-repo reuse = hoist shared base (adeba9f pattern); cross-repo = native implementation to cited semantics |
| P-D9 | Branch decision | Everything on `feature/SBE-1125`, per-story commit scopes, user commits |

### P-D10: Concurrency hazard analysis (release-level)

- New paths concurrent with existing ones against PT rows? **Yes** — refund/cancel/void/Mark-as-Paid all write PT while charge/retry crons read. Mitigation: every admin write is a guarded transition (`updateMany` with status-in-where → affected-count check), crons carry the U9 `payment_type=credit_card` guard, and void/cascade set `next_retry_at:null` so retry can never resurrect a row. Webhook remains sole writer of `succeeded` for card rows; U11 writes `succeeded` only for manual rows — disjoint by U7.
- Higher emission rate? **No** — reminder cron is daily, dedupe-per-interval vs notification_logs.
- New auto-triggered action? **Yes** — reminder cron. Mitigation: overlap guard (task-level, cloned pattern), settings-gated hour, manual rows only.
- Concurrency-control constants changed? **No.**

---

## Files (by phase — summary; step-level detail in Implementation Order)

| Phase | Repo | Files (action) |
|---|---|---|
| 1 (24.9) | admin | migration `add_refunds_and_refund_failed` (CREATE); `src/admin/orders/services/order-refund.service.ts` + DTOs + controller routes (CREATE/MODIFY); permission seeder (MODIFY: `orders.refund`) |
| 1 | external-api | `webhook.service.ts` handleChargeRefunded rework (MODIFY); internal Stripe refund wrapper endpoint/service (CREATE); schema mirror (MODIFY) |
| 1 | exhibitor/worker/pulse | schema mirrors (MODIFY, db push) |
| 2 (24.10) | admin | `order-cancel.service.ts` + DTO + route (CREATE/MODIFY); `inventory.service.ts` +`releaseForOrder` (MODIFY); permission seeder (`orders.cancel`) |
| 3 (24.11) | admin | notification-template + trigger-event seeders (MODIFY: 2 slugs/templates); `order-notification.service.ts` (CREATE); cancel/refund DTO flag wiring (MODIFY) |
| 4 (24.8) | admin | migration `add_pt_payment_type_memo_nullable_stripe` (CREATE, incl. backfill + enum comment + `admin_manual`); `order-payment-plan.service.ts` + mapper + routes (CREATE/MODIFY); permission seeder (`orders.payment-plan.*`) |
| 4 | exhibitor/external/worker/pulse | schema mirrors; 5 PT-writer updates (`payment_type: credit_card`): exh payments.service.ts:261, cart.service.ts:1370, ppl checkout.service.ts:227, ext webhook.service.ts:730, admin ppl-service-provider-detail-view.service.ts:969; worker charge+retry cron guards (MODIFY) |
| 5 (24.7) | admin | `GET :id/payments` handler on orders controller + response DTOs (MODIFY/CREATE); permission seeder (`orders.payments.read`) |
| 6 (24.6) | admin | migration `add_order_additional_emails` (CREATE); `order-details.service.ts` (aggregate) + `order-update.service.ts` (PATCH + sales-rep) + void handler + derivation helpers + DTOs + routes (CREATE/MODIFY); permission seeder (4 keys) |
| 7 (24.15) | worker | `scheduler/payment-reminder/*.registrar.ts|.task.ts` + `jobs/payment-reminder/payment-reminder.service.ts` (CREATE); manual-trigger controller (MODIFY); settings seed w/ provenance comments |
| 7 | admin | template + trigger-event seeders (MODIFY: 2 reminder slugs/templates) |
| all | all 5 | spec files per repo test conventions (CREATE/MODIFY per phase) |

---

## Substrate Verification (Phase 0 — run once at kickoff, before Phase 1)

| # | Check | Command / inspection | Expected | If mismatch |
|---|-------|----------------------|----------|-------------|
| 1 | Branch state ×5 | `git rev-list --left-right --count feature/SBE-1125...origin/dev` | 0 ahead in all 5 repos | STOP — someone pushed to the branch; reconcile with Prantik before ff |
| 2 | Fast-forward ×5 | `git checkout feature/SBE-1125 && git merge --ff-only origin/dev` | clean ff | STOP — implies ahead>0; do not rebase without go-ahead |
| 3 | id-encryption route convention | Read post-PR#455 param handling (`src/common/crypto/id-field.util.ts` + newest orders routes) | Documented convention for `:id` params | Apply whatever the live convention is to ALL new routes; amend plan note |
| 4 | PT enum values | admin schema: PaymentTransactionStatus | scheduled/processing/succeeded/failed/canceled/refunded (no refund_failed yet) | If refund_failed exists, someone built ahead — reconcile |
| 5 | PaymentTransactionSource | admin schema | 6 values incl. admin_change_plan + admin_manual? | Gate assumed admin_manual is NEW in Phase 4 — if present, drop that migration line |
| 6 | Trigger-event seeder count | count entries | 29 (no order_canceled/order_refunded/payment_reminder_*) | Collision → pick per D5/U6 alternates + flag |
| 7 | Webhook refund handler | ext webhook.service.ts handleChargeRefunded | amount-blind (reads only charge.id) | If already amount-aware, Phase-1 step shrinks — verify & amend |
| 8 | Charge/retry cron predicates | worker payment-charge.service.ts | no payment_type guard yet | If guarded, Phase-4 worker step shrinks |
| 9 | Orders controller surface | route list | list + notes + 24.5's 7 routes; none of ours | Any of our routes present → parallel work collision; STOP |
| 10 | Seeder idempotency baseline | run admin seed on fresh DB | green before we touch it | Fix-forward only with Prantik's call |

**Phase 0 RESULTS (run 2026-07-03, evening): 10/10 PASSED — Phase 0 COMPLETE.**
- Branch: dev synced ×5 (moved again same evening: admin +PR#526 mimeType, exhibitor +SBE-1141 PR#289, external +SBE-1171 PR#90); `feature/SBE-1125` fast-forwarded clean ×5 — **build pins: admin@142ddd9, exhibitor@fc41bef, worker@fbfcd8c, external@d3d4b2b, pulse@ffd3e5a**; all trees checked out on the branch, clean.
- **Check 3 (id-encryption convention, BINDING for all new routes):** ids encrypted globally by `IdCryptoInterceptor` (app-wide in `app.module.ts:96`); route params declared `@RawParam('id', ParseIntIdPipe) id: number` (`raw-param.decorator` + `parse-int-id.pipe`, multi-param precedent `invoiceId` at orders.controller.ts:299); response-DTO ids auto-encrypted by the interceptor — DTOs use plain Int ids; denylist auto-derives from Prisma DMMF (string ids like stripe_* never encrypted).
- **Check 5 correction:** `PaymentTransactionSource` = **5 values** (`admin_manual` NOT present — Phase 4.1 adds it as planned). The 24.15 doc's "6 values" evidence note is wrong → fix in the Step-8 doc pass.
- Checks 4/6/7/8/9 confirmed plan assumptions verbatim: no `refund_failed`; 29 trigger slugs, zero collisions; `handleChargeRefunded` amount-blind (webhook.service.ts:3038, PT lookup by charge id only); charge/retry crons unguarded; orders controller = 10 routes, none of ours.
- **Check 10 (run post-resumption, same evening): PASSED.** Disposable DB `sbe_phase0_check10` on local Postgres 18.3: `prisma migrate deploy` applied ALL migrations cleanly on a fresh DB; full DB seed suite (`run-seeds.ts`) green pass 1; pass 2 idempotent — exit 0, all "Skipped existing"/completed, row counts identical (permissions 237, roles 11, roles_permissions 380, users 4, notification_templates 23, trigger_events 26, configuration 22, products 8, boards 18). DB dropped after. Two recorded caveats, neither ours, neither blocking: **(a) pre-existing dev drift** between migrations and schema.prisma (legacy `fk_*` FK names, `updated_at` defaults, index diffs — pre-migrations baseline; plus `role_permission_audit_logs` dropped by migration 20260424 but still modeled in schema.prisma, Apr-2026 authors Kshitiz/Sushobhan Manna) — our Phase-1+ migrations must be authored with this drift in mind (`migrate dev` against a drifted DB would try to "fix" it — author migration SQL scoped to OUR changes only, per repo norm of hand-dated migration folders); **(b) `seed:plans` (subscription plans) is not locally runnable by design** — requires `STRIPE_SECRET_KEY` (absent from .env) and talks to live Stripe; out of check-10 scope.

---

## Implementation Order

> Per-phase pattern: build → spec tests green locally → Prantik reviews & commits (`type(SBE-11xx):` scope) → next phase. Pushes + pipeline checks batched at Prantik's discretion. Every step's full field-level spec = the story doc rows named in the step.
>
> **PRE-PUSH RULE (Prantik directive 2026-07-03, learned in Phase 1):** before ANY push, run the full canonical pre-push gate on every repo with changes — `scripts/pre-push-check-<repo>.sh` (admin = 8 steps incl. db:reset + seed, needs Prantik's consent for the reset; others = 6 steps npm ci → generate → typecheck → lint:check → test:cov → build). In Phase 1 these were run only AFTER pushing; from Phase 2 on they gate the push itself. Also budget a **rebase-onto-dev + full gate re-run** whenever dev moves between build and push (Phase 1 needed one: SBE-758/SBE-1175 landed mid-phase).

### Phase 1 — 24.9 Refund Management (SBE-1133) — U1, U2, U3

| Step | What | Spec rows |
|---|---|---|
| 1.1 | Migration: `refunds` ledger table (per-installment rows: pt_id FK, amount, method stripe|manual, reason/memo, actor, stripe_refund_id nullable, status) + `refund_failed` → PaymentTransactionStatus + `orders.refund` permission seed | 24.9-a…e, doc D1 |
| 1.2 | external-api: internal Stripe refund wrapper (stripe.refunds.create; idempotency key; maps Stripe errors) | 24.9-d/e, doc D2 leg |
| 1.3 | external-api: handleChargeRefunded rework — amount-aware, ledger-consistent (partial refunds recognized; PT → refunded only at full; refund_failed on failure path) | 24.9 D2 |
| 1.4 | admin: `POST /orders/:id/refunds` — per-installment selection (primitive) + order-level composition; eligibility: Stripe option iff `stripe_charge_id` present, Manual always (delivers 24.9-f both halves — manual rows never have charge ids, so Manual-only auto-materializes when Phase 4 creates them); validation caps vs paid/ledger; audit | 24.9-a…h |
| 1.5 | Derivations: OrderStatus.refunded / balance figures remain DERIVED (gross paid_amount − ledger) — helper in orders module | 24.9 D1/D3, U3, U20 |
| **Gate** | Refund a seeded card order end-to-end against Stripe test mode: ledger row, PT transition, webhook reconciliation; spec tests green | |

**Phase 1 MERGE STATE (2026-07-03 evening): 4/5 repos MERGED TO DEV** — pulse (PR#15), worker (PR#26), exhibitor (PR#292), admin (PR#529, after Sonar fixes `9b23b0f`: planLegs split into planTargetedLeg/planCompositionLegs S3776/S7735 + DTO ternary flatten S3358). **external PR#93 STAYS OPEN (Prantik decision):** our Sonar issue fixed (`b98281d` SETTLED_PT_STATUSES → Set S7776) but the gate stays red on an INHERITED violation — SBE-1175 commit `e8b75fa` (Manish Gun, 2026-07-03) added the $0-invoice branch inside `extractInlinePaymentIntent` (ppl-checkout.service.ts:603, function by Kshitiz a94362d) pushing complexity to 17>15; PR#91 had merged with a red pipeline (#129). Register rows for Step 8: inherited-debt-blocks-gate on shared Sonar project + red-gate-merge process gap (PR#91). Branches were rebased onto dev mid-phase (SBE-758/SBE-1175, zero conflicts, full local gates re-run green) before PRs. Full pre-push gates ran 5/5 green (post-push — see PRE-PUSH RULE above, now mandatory pre-push).

**Phase 1 STATUS (2026-07-03): BUILT + REVIEWED + SMOKED — committed & pushed (see MERGE STATE).** Build via 3 workflow rounds (24+12+8 agents): initial build → 14 confirmed review findings fixed (cap FOR UPDATE locks, webhook metadata matching `admin_refund_id`, ambiguous-outcome-stays-pending, D1-consistent webhook derivation, status mapping, DTO hardening) → 3 residual gaps closed (stripe.refunds.list fallback, stranded-leg voiding incl. finalize-failure path, PT-first lock ordering + out-of-tx P2002 recovery). Gates green: admin 3064 tests, external 556, exhibitor 1854; lint+tsc clean ×3. **Live smoke green** (local stack, Stripe TEST mode, real charges/refunds): refund-options caps/methods/newest-first ✓; partial $40 Stripe refund (PT stays succeeded) ✓; over-cap 400 ✓; missing-reason 400 ✓; full-remaining $60 (PT→refunded) ✓; manual $100 w/ memo (no Stripe call, PT→refunded, **order derived refunded with scheduled PT ignored**) ✓; paid_amount stayed gross 200 ✓; 3 audit rows w/ reason ✓; self-signed `charge.refunded` delivery → 200, idempotent (3 ledger rows, no dupes), live refunds carried `admin_refund_id` metadata ✓. **Smoke caught + fixed: role.seeder.ts Super Administrator list needed the 2 new keys (precedent 24.1-24.5).** Registered (story-doc register at Step 8): async `refund.failed`/`refund.updated` coverage deferred per 24.9-g gate wording; truly-orphaned pending rows (Stripe never reached) = ops reconciliation; refunds.list capped at 100/no pagination; webhook lock-order twin note (external must keep locking PT first). Smoke residue in local DB: order 1 `SMOKE-1133-ORDER` (cart 1, PTs 1-3, 3 refunds, fully refunded) + 2 Stripe test charges — left for inspection. Local `.env` gap found: admin needs `ID_ENCRYPTION_KEY` + `EXTERNAL_BACKEND_URL` + `EXTERNAL_APPLICATION_AUTHORIZATION_KEY` (injected inline for smoke, not written to file).

### Phase 2 — 24.10 Order Cancellation (SBE-1134) — U4, U5

| Step | What | Spec rows |
|---|---|---|
| 2.1 | admin: `POST /orders/:id/cancel` two-phase (`?confirm=` preview → confirm): tx = status→canceled + PT cascade (scheduled→canceled, `next_retry_at:null`, widened where) + optional refund composition via Phase-1 service (never re-implemented) + audit; `orders.cancel` seed | 24.10-a…i, j→U1 |
| 2.2 | admin: `InventoryService.releaseForOrder(orderId, tx)` (committed→released updateMany, `cart_id != null` guard) called in the cancel tx | 24.10-k |
| **Gate** | Cancel paths (never-paid / no-refund / partial / full) leave consistent PT + inventory + ledger state in one tx; spec tests green | |

**Phase 2 MERGED to dev (2026-07-04, verified via merge-base):** admin through `8588d3f` (incl. Sonar-fix round: S3776/S3358 extraction in cancel service, S6582 inventory optional chain, Swagger corrections — processing-blocks-409 wording + dual 409 examples via multi-message `ApiConflictErrorResponse`) and external through `38db6f6` (canceled-sticky). External PR merged red BY TEAM DECISION — its only Sonar issue is manish.gun's inherited S3776 (`ppl-checkout.service.ts#603`, from `e8b75fa`), zero issues ours (verified against the PR's own 2026-07-04 scan). Prepared fix for the inherited issue parked LOCALLY on external branch `fix/sonar-s3776-manish-gun-ppl-checkout` (`78185ad`, cut from dev, gates green; remote deleted on request — push + PR when Prantik says so). NOTE: external quality gate stays red for future PRs until that fix (or another) lands on dev. **RESOLVED 2026-07-04 (post-Phase-4): the parked fix was rebased onto current dev, gates re-run green (596 tests), pushed as PR#96 (pipeline #137 SUCCESSFUL incl. SonarQube gate), and MERGED to dev (`c6d9dd1`). Inherited S3776 cleared — external's Sonar gate is now GREEN; no more red-merge workaround. Fix branch deleted (local + remote); `feature/SBE-1125` rebased onto dev + force-pushed. Register item CLOSED.**

**Phase 2 STATUS (2026-07-03 late evening; committed+pushed 2026-07-04): COMPLETE — gates green, COMMITTED + PUSHED.** Pre-push gates per the PRE-PUSH RULE: admin 8-step green (fresh db reset + migrate deploy + seeds, typecheck, lint, **3114/3114 tests**, build), external 6-step green on 2nd run (**581/581**; 1st run hit a jest-worker SIGSEGV infra flake in the unrelated hubspot suite — not a test failure). Only admin+external carried changes; exhibitor/worker/pulse clean → not gated. Commits: admin `56d0509` fix(SBE-1133) idempotency-key + helper hoists, `c21c04b` feat(SBE-1134) cancel feature; external `38db6f6` fix(SBE-1134) canceled-sticky. All pushed to `origin/feature/SBE-1125`. Build (resumed workflow post Phase-1-merge interrupt; stash-pop conflicts reconciled with the Sonar refactor): two-phase `?confirm=` cancel endpoint, cancel tx (PT FOR UPDATE locks → guarded flip → cascade scheduled/failed → releaseForOrder → audit-as-requested), refund via 24.9 composition post-commit, zero cancel-owned refund code (fan-out hoisted to `distributeRefundNewestFirst`), `orders.cancel` in both seeders. Review: 6 confirmed findings fixed + verified (C1 processing-blocks-409 incl. in-tx TOCTOU re-check; C2 shared PT-lock hoist/webhook lock order; C3 truthful uncertain-state message; C4 refund-requested audit; C5 doc-only). Cross-repo fix (user-approved): external `computeNewOrderStatus` makes **canceled STICKY** (payment webhook never resurrects; money still recorded → refund-options) + spec. **Smoke caught defect #7 (fixed): Stripe idempotency key was `refund-<rowId>` — collides across DB resets/environments sharing a test account; now `refund-<rowId>-<created_at ms>`** (specs updated; the collision live-exercised the ambiguous-outcome path end-to-end: leg pending+cap reserved, sibling voided w/ memo, 502 explained, retry 409 — all as designed). Smoke matrix green: processing→409 both phases ✓; partial-no-amount 400 ✓; preview = zero writes ✓; cancel-only (never-paid: cascade+null next_retry_at, `no refundable amount` audit) ✓; full cancel-with-refund (cascade+reservation released committed→released+2 real Stripe legs) ✓; already-canceled 409 ✓; standalone $200 refund on canceled order → 2 legs succeeded, PTs refunded, **order derived canceled→refunded per D1** (record for 24.6 status_display: fully-refunded canceled orders end `refunded`) ✓; partial $40 cancel (order stays canceled, PT stays succeeded, real refund, gross paid intact) ✓; audit trail two-record shape (cancel-requested + leg-initiated) ✓. Gates at smoke end: admin 335/335 scoped (3113 full at gate run), external 233/233 webhook, lint+tsc clean. Ops note: refunds row #1 operator-voided via SQL (the registered orphaned-pending action, live-exercised). Smoke fixtures SMOKE-1134-A/B/C/E left in local DB.

### Phase 3 — 24.11 Cancel/Refund Emails (SBE-1135) — U6

| Step | What | Spec rows |
|---|---|---|
| 3.1 | Seeders: `order_canceled` + `order_refunded` trigger slugs + EMAIL templates (append-only; META guard passes) | 24.11-c, D1/D2 |
| 3.2 | admin: notification service — recipient chain (billing_email → company contact → skip+log), POST-COMMIT dispatch via admin mailer (non-throwing pattern), one-email-per-action (cancel sends order_canceled w/ optional refund tokens; standalone refund sends order_refunded; never both) | 24.11-a…e, D1/D3 |
| 3.3 | Wire `send_email` boolean (default true) into Phase-1/2 DTOs; backend-enforced | 24.11-a/b/d/e |
| **Gate** | Flag on/off matrix verified: exactly one email per action, correct template + recipients, no email on unchecked; spec tests green | |

**Phase 3 STATUS (2026-07-04): BUILT + REVIEWED — awaiting live smoke + Prantik's commit gate.** Pre-build: all 5 repos rebased onto dev (branch tips == dev tips, force-pushed with lease; admin needed `prisma generate` first — dev brought gift-certificate `stripe_product_id` + `Order.discount`; local DB needs `migrate deploy` before smoke). Build (12-agent workflow): `order-notification.service.ts` (single P-D8 home: D3 recipient chain billing_email→company primary account holder→skip+logActivity, token building, non-throwing on top of the mailer's non-throwing) + 2 seeded trigger_events w/ placeholder sets + 2 EMAIL templates w/ TEMPLATE_META (tag Store, blank-safe refund tokens "None"/"Not applicable") + `LAYOUT_BY_NOTIFICATION_TYPE` user-layout rows + one-email-per-action via `createRefund(..., { suppressNotification })` (cancel always suppresses and owns the single `order_canceled` send post-flow) + DTO description updates. 20 new tests; full admin gates green: lint 0, tsc 0, **3134/3134**. Review (3 lenses + adversarial verify): 5 confirmed findings, ALL minor. FIXED: #3 false-announcement window — `order_refunded` template wording "processed"→"initiated" (pending Stripe legs count toward the announced amount and can still fail; wording now true in all outcomes; why-comment in seeder). REGISTERED as deliberate/accepted (Step-8 rows): (#1) refund-step failure after the committed cancel tx suppresses `order_canceled` (never announce a failed/uncertain refund; standalone-refund retry then emails only `order_refunded`); (#2) all-legs-declined standalone refund returns 200 but skips the email (a "refund initiated" mail would be false; skip is logged); (#4) same suppression on the 502-ambiguous leg path (twin of #1); (#5) E&S known-issue #21 shadowing now also covers the two new slugs (pre-existing `findFirst` without `is_predefined`; fix ships with E&S scheduling). #1/#2/#4 = product-behavior calls for BA visibility, not defects. **Prantik decision 2026-07-04: record-only, no further fixes this phase.** Candidate fix for #1/#4 noted for the BA/Step-8 row (NOT built): on the refund-step-failure path, send `order_canceled` with neutral refund tokens ("Being finalized" / "You will receive a separate confirmation") — truthful, no template change, ~20 lines + 3 specs whenever approved. #2's only truthful fix would be a THIRD "refund attempt failed" trigger+template — outside D1's locked two-slug scope; BA to bless the skip or commission it as new scope. Review loop CLOSED (3 lenses + adversarial verify + post-fix green re-run). **LIVE SMOKE GREEN (2026-07-04, real SendGrid sends, manual-refund path — admin service only):** DB migrate-deployed (dev's new migrations) + re-seeded (both slugs + templates landed w/ "initiated" wording). Matrix (fixtures SMOKE-1135-A…F, @example.com recipients): A standalone refund flag on → `order_refunded` SENT to billing_email, tokens rendered ($100.00/manual/name, zero unrendered `{{`) ✓; B cancel-with-refund flag OMITTED → default-true proven, ONLY `order_canceled` sent (refund executed but no `order_refunded` — one-email-per-action live) w/ refund tokens rendered ✓; C cancel never-paid → `order_canceled` w/ blank-safe "None"/"Not applicable" ✓; D flag=false → action 200, ZERO emails, audit rows record send_notification:false ✓; E billing_email NULL → fallback recipient (company primary account holder smoke-1135-fallback@) used ✓; F no email anywhere → cancel+refund still succeed, skip logged ("no billing email and no company contact email") ✓. notification_logs = exactly 4 rows, all status SENT (SendGrid accepted). End-state consistency: A/B/D/E/F derived `refunded`, C `canceled`, paid_amount gross intact. Fixtures left in local DB. **COMMITTED + PUSHED 2026-07-04:** admin `f614a53` feat(SBE-1135) on `origin/feature/SBE-1125` (12 files, +992/−28). Pre-push 8-step gate green immediately before (fresh DB, seeds incl. both new artifacts on virgin DB, tsc 0, lint 0, 3134/3134, build OK; husky pre-push re-ran typecheck+lint on the push itself). Phase 3 MERGED to dev (PR#532, pipeline #871 all-green incl. Sonar; merge-base verified 2026-07-04). Branch rebased onto dev (tip == dev 8ec45fd) and force-pushed. **STORY 24.11 COMPLETE.** Phase 4 (24.8) awaits go-ahead.

### Phase 4 — 24.8 Payment Plan Management (SBE-1132) — U7–U12

| Step | What | Spec rows |
|---|---|---|
| 4.1 | Migration: `payment_type` (CartPaymentMethod reuse; backfill credit_card; NOT NULL, no default; doc-comments on enum + column) + `payment_memo` (nullable) + stripe_pm/cus nullable w/ why-comments + `admin_manual` source value; mirrors to 4 repos (db push) | 24.8-a/b, D2/D3/D4 |
| 4.2 | 5 PT-writer updates: add `payment_type: credit_card` at the verified card-flow creation sites (exh payments/cart/ppl-checkout, ext webhook, admin ppl) | 24.8 D2 |
| 4.3 | worker: charge + retry cron guards `payment_type = credit_card` | 24.8 D3, U9 |
| 4.4 | admin: C13 mapper (PT → installment rows: D1 label map, amounts, dates, invoice #, payment_type, payment_memo) as a shared orders-module helper — single home, consumed by Phases 5/6 | 24.8-e…h, U10 |
| 4.5 | admin: plan routes — plan view + scheduled-only installment edit/delete + `PATCH :id/payment-plan/installments/:installmentId` Mark-as-Paid/Unpaid (manual-method-only gate; Paid→succeeded+paid_at+money writes mirroring webhook; Unpaid→scheduled+reversal — the one legit gross decrement); plan-level lock `paid_in_full_at`; in-tx derived unallocated; null-show-date skip+warn; UUID idempotency; two-phase confirm (shared-base hoist if reusing cart's confirm helper — P-D8); `orders.payment-plan.*` seeds; audit | 24.8-c/d/i/j/k/m + l-display |
| **Gate** | Manual lifecycle end-to-end: create manual installment → appears Unpaid → Mark-as-Paid → money/status verified → Unpaid reversal verified; crons ignore manual rows; spec tests green | |

**Phase 4 STATUS (2026-07-04): COMPLETE — COMMITTED + PUSHED (all 5 repos), awaiting Prantik's PRs.** Pre-build: external rebased onto dev `b855198` (schema-sync incl. `admin_change_plan`), other 4 already == dev. Build (Opus workflow, 24 agents: recon→build→gates→3 review lenses→adversarial verify; Fable exhausted mid-run, paused via TaskStop + resumed on Opus from cache — recon+build banked). Delivered: migration `add_pt_payment_type_memo_nullable_stripe` (payment_type CartPaymentMethod backfill credit_card NOT NULL no-default + payment_memo nullable + stripe cols nullable + `admin_manual` source; doc-comments in SQL AND schema; worker/pulse mirror also gained the previously-missing `admin_change_plan` + full `CartPaymentMethod` enum) applied on fresh DB; C13 mapper (single exported home for 24.7/24.6/24.15); GET plan + POST/PATCH/DELETE routes (two-phase `?confirm=`, in-tx unallocated cap, non-CC memo, card-sibling Stripe-id copy, scheduled-only + manual-only guards, Mark-Paid/Unpaid money mirror/reversal = the one legit gross decrement, plan lock); 5 PT-writer `payment_type: credit_card` additions + worker charge/retry cron guards; `orders.payment-plan.*` permission+role seeds; audit per mutation. **Review: 9 confirmed findings → 5 unique.** Two CRITICAL compile-blockers FIXED (the D2 no-default made `payment_type` required at 2 card-writer sites the 5-site enumeration missed — F1 exhibitor `ppl.service.ts` PPL-checkout create; F2 external `webhook.service.ts` failed-renewal `upsert` create arm — grep only matched `.create`). Two majors FIXED (Prantik-approved): **F4** terminal-status guard — canceled/refunded orders reject add/reschedule/Mark-Paid/delete (Mark-Unpaid exempt: reversal is a correction) via `assertOrderMutable`, closes a cron-charges-canceled-order hole cancellation leaves open (paid_in_full_at stays null); **P4-03** `FOR UPDATE` on the order row in `lockAndReload` so zero-installment adds serialize (empty PT-list = no-op PT lock). One major RECORDED not fixed (Prantik decision): **F3** `paid_amount` lost-update — admin Mark-Paid/Unpaid AND the external webhook both absolute-write `paid_amount` under READ COMMITTED; the admin side alone can't close it (webhook's unlocked read + absolute write clobbers), full fix = atomic `{increment}`/`{decrement}` on BOTH writers (external webhook = sensitive payment path, pre-existing webhook-vs-webhook race, outside 24.8's admin module) → **register/BA payment-path hardening ticket**. **LIVE SMOKE GREEN (2026-07-04, booted admin :3333, real HTTP + encrypted-id auth, fixtures SMOKE-1132-A active split / B canceled):** GET mapper rows+milestone labels+derived unallocated+null-show-date warning ✓; add manual (admin_manual, UUID key, null Stripe) + add card (sibling Stripe-id copy) ✓; cap/memo/preview rejects ✓; Mark-Paid 500→800 then Unpaid 800→500 (gross decrement) + date-edit + delete (unallocated returned) + 6 audit rows ✓; card-forbidden/scheduled-only/XOR guards ✓; **F4** add-to-canceled → 409 ORDER_NOT_MUTABLE + Mark-Unpaid exemption (B 500→0, stays canceled) ✓; plan lock 409 ✓; D3 cron-skip (guarded query selects only card rows) ✓. **Smoke caught + FIXED a nested-id contract bug:** GET emits encrypted `payment_transaction_id` but PATCH/DELETE `:installmentId` (camelCase) was NOT decrypted by the global `IdCryptoInterceptor` (only matches `id`/`*_id`) — an FE consuming the response couldn't call the route. Fixed by renaming the route param `:installmentId`→`:installment_id` (Option 1, Prantik-approved) so `endsWith('_id')` decrypts it; re-verified live (encrypted token 200, raw int now 400 "Invalid identifier" — opaque both ways). Pre-existing sibling-route twins (`:itemId`/`:showProductId`/`:invoiceId` on cart/invoices) = register row (Option 2, separate hardening). **Pre-push gates GREEN ×5:** admin 8-step (fresh DB reset+migrate+seed on virgin DB, **3236 tests**, build), exhibitor 6-step **2004** (1 flaky fail on `isDeepEmail` live-MX lookup during the parallel run — network blip, unrelated to our files, green on isolated + full re-run), external **596**, worker **291**, pulse **127**; lint+tsc clean ×5. **COMMITTED + PUSHED 2026-07-04:** admin `81f6fd9`, exhibitor `6f84347`, external `407a20d`, worker `d4206c3`, pulse `3127e17` → `origin/feature/SBE-1125` (per-ticket `feat(SBE-1132)` scope, no AI trailers; exhibitor pre-commit hook ran the full 2004 suite). Smoke fixtures wiped by the admin gate's DB reset. Step-8 register carries: F3 payment-path hardening, nested-id sibling-route inconsistency (itemId/showProductId/invoiceId), 24.8-l chargeback/QB automation halves. Pipelines: 4/5 green; external PR#95 failed only the SonarQube gate on manish.gun's inherited S3776 (`ppl-checkout.service.ts#603`) — our SBE-1132 change (webhook + schema) had ZERO new-code issues (author-verified). **Phase 4 MERGED to dev (2026-07-04, all 5 PRs — admin #533/exhibitor #298/worker #27/external #95/pulse #16; external red-merged BY TEAM DECISION, inherited-not-ours per the PR#91/#93 precedent; merge-base verified). Branch rebased onto dev + force-pushed, all 5 == dev (admin acbb3f1, exhibitor c0bdf97, external 5986d3d, worker 57fa323, pulse c4a9d4b). Swagger verified complete in code (admin 4 routes + DTOs; siblings no API surface). STORY 24.8 COMPLETE.** Phase 5 (24.7) awaits go-ahead.

### Phase 5 — 24.7 Payments View (SBE-1131) — U13

| Step | What | Spec rows |
|---|---|---|
| 5.1 | admin: `GET /orders/:id/payments` = U10 rows + order money summary + derived Paid/Unpaid label (native implementation of `deriveOrderPaymentStatus` semantics — P-D8); `orders.payments.read` seed; Swagger (FE reads method enum from DTOs) | 24.7-a/e (b/c/d delivered by 4.5) |
| **Gate** | Route returns correct rows/labels for card, manual, refunded, voided fixtures; spec tests green | |

**Phase 5 STATUS (2026-07-04): COMPLETE — COMMITTED + PUSHED (admin only), awaiting Prantik's PR.** All 5 repos == dev at start (external at c6d9dd1 after the manish.gun fix merged). ADMIN-ONLY phase — siblings untouched. Build (lean Opus workflow, 6 agents: 2 recon → build → gate → 2 review lenses → adversarial verify): ONE read route `GET /api/v1/orders/:id/payments` (`@Permissions('orders.payments.read')`, `@RawParam('id', ParseIntIdPipe)`, ownership-404, `Order.notes` never selected) in a new `OrderPaymentsService` — installment rows via 24.8's EXPORTED C13 mapper `mapInstallmentRow` (REUSED, not duplicated — P-D8); order money summary (total/paid_amount/balance_due fixed-2 + paid_in_full_at); derived Paid/Unpaid label via NEW native `deriveOrderPaymentStatus`/`deriveOrderPaidLabel` (Decimal-exact, GROSS paid_amount per P-D1, NEVER consults `Order.status` — faithful port of exhibitor semantics); `OrderPaymentsResponseDto` + `OrderPaymentLabel` enum w/ full `@ApiProperty`; `orders.payments.read` seeded in BOTH permission.seeder + role.seeder (adminPermissions). **NO write path (P-D5 — Mark-Paid/Unpaid stays in 24.8's PATCH); route distinct from GET :id/payment-plan.** **Reviews: TWO independent passes, ZERO findings** — build's 2-lens (spec + correctness/security) + a fresh 4-lens skeptical re-review (label-correctness, mapper-reuse/scope, security/permissions, swagger/DTO/integration), all empty after adversarial verify. **LIVE SMOKE GREEN (2026-07-04, booted admin :3333, real HTTP + encrypted-id auth, fixtures SMOKE-1131-A…D):** A mixed card+manual partial → label Unpaid, 3 rows w/ per-installment memo "Check #501" ✓; B fully paid → Paid ✓; C gross-refunded → order label Paid (gross) while row shows Refunded — coherent ✓; D voided → Unpaid, row Canceled ✓; raw-int id → 400 "Invalid identifier"; unauthenticated → 401; response carries NO `notes` field ✓. **Pre-push gate GREEN (admin 8-step): fresh DB reset+migrate+seed on virgin DB (`orders.payments.read` lands), typecheck, lint, 3258 tests, build; siblings clean (0 changes) → not gated.** **COMMITTED + PUSHED 2026-07-04:** admin `83f56dc` feat(SBE-1131) → `origin/feature/SBE-1125`. **MERGED to dev (PR#534, pipeline #873 SUCCESSFUL incl. SonarQube — admin clean, no inherited debt; merge-base verified 2026-07-04). Branch rebased onto dev (== dev a3d36f1) + force-pushed; all 5 repos == dev. STORY 24.7 COMPLETE.** Phase 6 (24.6) awaits go-ahead.

### Phase 6 — 24.6 Order Details (SBE-1130) — U14–U18

| Step | What | Spec rows |
|---|---|---|
| 6.1 | Migration: `Order.additional_emails` Json + permission seeds (`orders.view/update/sales_rep.update/payments.void`) | 24.6-i/y |
| 6.2 | admin: derivation helpers — `status_display` (D1 six-value map over status + ledger arithmetic) + rep/source chain (D3) — native, shared within orders module | 24.6-b/j/t |
| 6.3 | admin: `GET /orders/:id` aggregate — general, notes/memo/terms (read-only; `Order.notes` NEVER exposed), billing, additional_emails, customer link, line-item tree w/ flat fallback + `cart.coupon.code` join, onsite-contact ABSENT (deferred), fees, totals + items-subtotal/fees breakdown (C10), plan block via U10 + next-installment query, signer, agreement/payments links, sales rep object | 24.6-a,c…h,k,l,m,n,o,p,q,s-link |
| 6.4 | admin: `PATCH /orders/:id` (billing + additional_emails; 24.6-aa status matrix from Status Breakdowns; audit) + `PATCH :id/sales-rep` (deal-owner-pattern validation → sales_person_id; dropdown source decision: reuse `GET carts/deal-owners` if cleanly consumable, else own endpoint) | 24.6-h/i/u/aa |
| 6.5 | admin: `POST /orders/:id/payments/:transactionId/void` — guard status IN (scheduled, failed) → canceled + next_retry_at:null; "Voided" label via U10; audit | 24.6-z void half (refund half = flags wired to Phase 1) |
| **Gate** | Aggregate correct for: exhibitor-created (full billing, tree), admin-created (null billing, flat — graceful), multi-show, subscription (no cart), refunded, cancelled fixtures; edit matrix blocks per status; void end-to-end; spec tests green | |

**Phase 6 STATUS (2026-07-04): IN PROGRESS — BUILD + REVIEW + LABEL-FIX DONE (uncommitted); LIVE SMOKE HELD at Prantik's request pending discussion.** Admin-only phase; branch `feature/SBE-1125` tip `a3d36f1` (== dev), **24 uncommitted files** in the admin working tree (other 4 repos clean). Build (Opus workflow, 14 agents: 5 recon → sequential B1-B4 build → gate → 4 review lenses → adversarial verify): migration `20260704130000_add_order_additional_emails` (jsonb NOT NULL `'[]'`) applied locally + 4 permission seeds (`orders.view/update/sales_rep.update/payments.void`) in BOTH seeders; native `deriveOrderStatusDisplay` (6-value D1 status_display, Cancelled qualifiers from 24.9 ledger) + `deriveOrderSource` (D3 chain); `GET /orders/:id` aggregate (`order-details.service.ts` + `order-details.helpers.ts` native classifyOrderItems tree + FLAT FALLBACK, coupon via cart.coupon.code, plan block via REUSED C13 `mapInstallmentRow` + next-installment, signer, totals breakdown, balance net of refund ledger, `Order.notes` NEVER selected); `PATCH /orders/:id` (billing + additional_emails, status-gated: editable only while pending/partially_paid/failed, canceled/completed/refunded → 409) + `PATCH :id/sales-rep` (native deal-owner eligibility validation, NO HubSpot) + `POST :id/payments/:transaction_id/void` (D-z; **snake_case param** per Phase-4 lesson; guarded transition → canceled + `next_retry_at:null` mirroring 24.10; `orders.payments.void`). Full Swagger + DTOs. **Reviews: 4 lenses (spec rows a-aa, derivations/money, aggregate/tree, security/writes/void) + adversarial verify → ZERO confirmed findings.** **LABEL FIX (Prantik-approved 2026-07-04):** relabelled shared `MILESTONE_STATUS_LABELS` to the U10/D1 sheet map — `scheduled→Unpaid, failed→CC Failed, canceled→Voided` (Paid/Refunded unchanged; Processing/Refund Failed no sheet row, left literal). Root cause = Phase-4 build-brief drift (referenced "per D1" but didn't inline D1's exact strings, which live in the 24.6 doc + ledger U10; 24.8 build defaulted to enum literals; 24.8/24.7 review+smoke didn't pin wording). Fix satisfies 24.6-q + 24.6-z exactly AND corrects 24.7/24.8's already-merged installment displays to U10 (aligned in one place; ~7 assertions + Swagger example + 2 comments updated). Verified NO sibling requirement broken — U10 always specified this map (single source); 24.15 doesn't consume the mapper. **Process lesson recorded in the shared-unit ledger (`25ac20a`, pushed): inline the ledger's exact spec into each consuming build brief.** **GATE CAVEAT (honest):** the workflow's FULL-suite gate (**3335/3335**, 1 jest-SIGSEGV flake passing standalone) ran BEFORE the relabel; post-relabel only the **orders module was re-run (520/520 green)** — the full suite gets re-verified at the pre-push gate. **REMAINING (all held):** (1) live smoke — SMOKE-1130 fixtures LOADED in local DB (EX exhibitor-tree / AD admin-flat / SUB subscription-no-cart / CX cancelled+partial-refund / VD void-target); app was about to boot when Prantik paused for further confirmations; (2) pre-push gate (admin 8-step); (3) commit/push (`feat(SBE-1130)`, admin only) + PR + merge + rebase; (4) Phase-6 STATUS finalization + the plan note that the relabel corrects 24.7/24.8. **Infra:** machine restarted mid-session (high memory) → resumed session; workspace-repo GitHub push auth restored via `core.sshCommand` → `/Users/uipl/Desktop/uipl/pmtool_key_file`. Phase 7 (24.15) not started.

### Phase 7 — 24.15 Payment Reminders (SBE-1139) — U19

| Step | What | Spec rows |
|---|---|---|
| 7.1 | admin seeders: `payment_reminder_upcoming`/`payment_reminder_overdue` slugs + EMAIL templates | 24.15-d |
| 7.2 | worker: settings family `payment_reminder_{upcoming_days,overdue_interval_days,hour_utc}` defaults 7/7/14 — **with gate-provenance doc-comments (P-D7 directive: defaults set at 2026-07-03 gate, not spec-derived; knob purpose; dedupe rule; BA ratification pending OQ-1)** | 24.15 D2 |
| 7.3 | worker: registrar/task/service triple (pattern-cloned structure, no lifted logic): upcoming predicate (scheduled, manual, within window) + overdue predicate (native deriveIsOverdue semantics, manual only) + notification_logs dedupe + stop = settled-set status read at send time; recipient billing_email; worker mailer dispatch | 24.15-a/b/c/e/f/g |
| 7.4 | worker: `POST manual-trigger/payment-reminders/run` (dev-only) | 24.15-h |
| 7.5 | File the scheduling-register hand-off note (OQ-4) — scheduling register ONLY | 24.15 D4 |
| **Gate** | Simulated clock run: upcoming fires at window, overdue repeats at interval w/ dedupe, stops on Paid (4.5) and Void (6.5); card rows never selected; spec tests green | |

---

### Phase 8 — Delivery Audit (release close-out; runs AFTER Phase 7)

**Why (added 2026-07-05):** the Phase-4 `MILESTONE_STATUS_LABELS` drift — build brief said "per D1" but didn't inline D1's exact strings, so 24.8 shipped enum literals (`Scheduled/Failed/Canceled`) that survived 24.8's + 24.7's reviews/smokes and only surfaced in Phase 6 (24.6-q/z name the exact sheet labels), fixed in the one shared place (`25ac20a` process lesson in the ledger). A single systematic audit at release end guarantees this class of loss/drift is caught by construction, not by luck. **Placement = after Phase 7 (not 6):** the release scope is all 7 stories, drift is cross-story (lived in 24.8, invisible through 24.7), and 24.15 doesn't consume the C13 mapper so nothing compounds by waiting one phase → one pass covers the complete delivered surface. **Read-only until Prantik approves any fix.**

| Step | What | Notes |
|---|---|---|
| 8.1 | Per-story requirement trace (fan-out, 1 auditor/story): for every row marked **Deliverable** / **Partial** in each story's plan-time feasibility `.xlsx`/`.md`, confirm a concrete MERGED artifact delivers it — route, service method, DTO field, permission key, migration column. Classify each: **verified / lost** (Deliverable with no landing spot) / **drifted** (delivered but contradicts the spec's exact wording, e.g. the labels). | Baseline = feasibility docs as they stood at plan kickoff; compare against dev tip |
| 8.2 | Shared-unit conformance: check EVERY consumer of each shared unit (U10/C13 `mapInstallmentRow`, `deriveOrderStatusDisplay`, derived Paid/Unpaid, permission seeds) against the ledger's authoritative spec — the exact failure mode that bit us | Uses `OM_PHASE1_SHARED_UNIT_LEDGER.md` as source of truth |
| 8.3 | Scope-creep / silent-change check: anything delivered that was NOT in the plan, or a verdict silently flipped from OutOfScope/Blocked/NotDeliverable without a recorded decision | |
| 8.4 | Adversarial critic pass ("what's missing / what drifted") over 8.1–8.3 findings, then synthesis into a reconciliation report: per-story Deliverable count → verified / lost / drifted, plus a prioritized fix list | Multi-agent: fan-out auditors → adversarial verify → synthesis |
| **Gate** | Reconciliation report delivered to Prantik; every plan-time Deliverable is either verified-delivered or has an approved fix item; zero unexplained drift/loss. Fixes (if any) proposed for review — no auto-commit. | |

---

## Tests

Per repo conventions (`*.spec.ts` beside sources; suites must stay green whole-repo). Minimum per phase: service-level specs for every new service/handler (happy + guard paths named in each Gate line); migration/backfill assertions where a phase carries a migration (4.1: backfill count = pre-migration PT count, NOT NULL holds, mirrors match); cross-phase regression at Phase 7: the Phase-1/2/4/6 suites re-run green (release suite, not just the phase's). Fixtures: shared order fixtures (card/manual/mixed plans, exhibitor/admin-created, multi-show) built once in Phase 1 and extended forward — hoisted into a shared test-fixture helper if any repo needs them twice (P-D8 applies to test code too).

## Backward Compatibility

- `payment_type` backfill `credit_card` + NOT NULL: verified true for all 5 historical creation sites (gate evidence) — no legacy row can violate it.
- Nullable relaxations (stripe_pm/cus) widen, never break, existing readers; why-comments mandatory (P-D4).
- New enum values (`refund_failed`, `admin_manual`) are additive; no exhaustive-switch may assume old cardinality (24.15-f evidence note).
- `paid_amount` semantics unchanged (gross — P-D1); Balance consumers switch to derived helper, list endpoint untouched.
- No existing route changes shape; all new routes additive on the shipped controller.

## Security Considerations

Every new route: JWT + RolesGuard + `@Permissions()` key per the ledger allocation table; ownership-404 select discipline (13.3 precedent) on the aggregate; refund/cancel/void/Mark-as-Paid all audit-logged with actor; Stripe refund wrapper is internal-only (service-to-service auth per existing external-api internal-route pattern); no secrets in code (gitleaks gate).

## Deferred (excluded by locked verdicts — ledger rule 6)

| Item | Verdict | Where tracked |
|---|---|---|
| 24.6-r send-order-email | Needs clarification | 24.6 OQ-4 |
| 24.6-v/x HubSpot deal sync | Needs clarification (no owning epic) | 24.6 OQ-5 |
| 24.6-w QuickBooks force sync; 24.9-i; 24.8-l QB actions | Blocked/OOS — epic 65 | story docs |
| 24.6-l2 per-item onsite contact | Deferred — SBE-1169/1171 | 24.6 OQ-3 |
| Chargeback trio statuses/webhooks | Not Deliverable | 24.8-l + sheet citation |
| additional_emails CC on automated sends | Pending one BA answer | 24.6 OQ-2 / 24.15 OQ-3 |
| SMS channel; cadence values final; departments@ cancel notify; refund-email extra-recipient | BA rows | 24.15 OQ-1 / 24.6 OQ-6 |

## Post-Atom Checklist (release close-out)

- [ ] Coverage Matrix (Appendix A) — every row checked against merged code
- [ ] Story docs + xlsx: Implementation Status sections updated per STORY_DOC_FORMAT_UPDATES (branch, commits, PR, gates, smoke)
- [ ] ORDER_EPICS_BUILD_CONSOLIDATION.md refreshed (stale items flagged at gate: source enum, 24.7 shrink, SBE-671 caveat, line refs)
- [ ] Scheduling-register hand-off note filed (7.5)
- [ ] Jira: 7 stories transitioned per team flow (only on explicit ask — read-only default)
- [ ] Memory ledger updated; plan status → implemented

## Quality Gates

- `npm run lint` + typecheck: 0 errors, all touched repos
- Full test suites green per repo (not just new specs)
- Pipelines green ×5: gitleaks → lint/typecheck/test → SonarQube (confirm which step failed before blaming Sonar)
- SonarQube: 0 new-code issues authored by us (fix only ours — standing rule); **duplication gate clean (P-D8)**
- Fresh-DB migrate + seed idempotent; `db push` mirrors diff-clean vs admin schema
- **Swagger/DTO annotations complete for every new or changed route** (each phase that adds/changes an API surface): `@ApiOperation` + success + error responses on the route, `@ApiParam`/`@ApiQuery` matching the live contract (incl. id-encryption param names), and `@ApiProperty` on every request/response DTO field. Repos with no API-surface change this phase are exempt (record "no surface" rather than skipping silently).

## Verification

1. Phase gates 1–7 each passed (binary lines above).
2. Release smoke on locally booted stack: the 9-route new surface + cron manual-trigger, against the fixture matrix (card/manual/mixed, exhibitor/admin-created, refund/cancel/void/remind lifecycle end-to-end).
3. Appendix A walked row-by-row against the diff — zero unmapped Deliverables, zero out-of-scope deliveries.
4. All 5 repos: branch pushed, pipelines + Sonar green (user-triggered), story docs' Implementation Status flipped.

---

## Appendix A — Deliverable Coverage Matrix (the release-level acceptance list)

**Rule:** every row must be delivered by its named step(s). "◻" flips to "✅" only at Post-Atom review.

| Req | Verdict source | Delivered by | |
|---|---|---|---|
| 24.9-a…e, g, h | Deliverable | Steps 1.1–1.5 | ◻ |
| 24.9-f | Partial → both halves | Step 1.4 (charge-id gate; Manual-only auto-materializes at Phase 4) | ◻ |
| 24.10-a…i | Deliverable | Steps 2.1 (+3.3 flag) | ◻ |
| 24.10-j | Covered by 24.9 | Step 1.4 | ◻ |
| 24.10-k | Deliverable (added) | Step 2.2 | ◻ |
| 24.11-a…e | Deliverable | Steps 3.1–3.3 | ◻ |
| 24.8-a, b | Deliverable | Steps 4.1–4.2 | ◻ |
| 24.8-c, d, i, j, k, m | Deliverable | Step 4.5 | ◻ |
| 24.8-e…h | Deliverable | Step 4.4 | ◻ |
| 24.8-l (display half) | Split-Deliverable | Steps 4.4 + 5.1 (labels rendered; QB/chargeback halves excluded) | ◻ |
| 24.7-a | Deliverable | Step 4.1 column + 5.1 exposure | ◻ |
| 24.7-b, c, d | Covered by 24.8 | Step 4.5 | ◻ |
| 24.7-e | Deliverable | Step 5.1 | ◻ |
| 24.6-a, g, k, l, n, o | Deliverable | Step 6.3 | ◻ |
| 24.6-b | Deliverable-seq (24.9) | Steps 6.2 + 6.3 (ledger from Phase 1) | ◻ |
| 24.6-c, d, e, f | Deliverable | Step 6.3 (display; 24.14 columns) | ◻ |
| 24.6-h | Deliverable | Steps 6.3 + 6.4 (gap → OQ-1, not code) | ◻ |
| 24.6-i | Deliverable | Steps 6.1 + 6.4 | ◻ |
| 24.6-j, t | Deliverable | Steps 6.2 + 6.3 | ◻ |
| 24.6-m | Deliverable | Step 6.3 (tree + flat fallback) | ◻ |
| 24.6-p, q | Deliverable-seq (24.8) | Step 6.3 via 4.4 | ◻ |
| 24.6-s | Covered by 24.5 (live) | pre-existing; 6.3 links | ◻ |
| 24.6-u | Deliverable | Step 6.4 | ◻ |
| 24.6-y | Deliverable | Steps 6.1 + route decorators (all phases' seeds) | ◻ |
| 24.6-z | Deliverable (split) | refund flags 6.3→Phase 1; void Step 6.5 | ◻ |
| 24.6-aa | Deliverable | Step 6.4 matrix (+6.5 guards) | ◻ |
| 24.15-a, b | Deliverable-seq (24.8) | Step 7.3 (predicates on 4.1's column) | ◻ |
| 24.15-c | Deliverable | Steps 7.2 + 7.3 | ◻ |
| 24.15-d | Deliverable | Step 7.1 | ◻ |
| 24.15-e, f, g | Deliverable-seq (24.8) | Step 7.3 (stop via 4.5/6.5 writes) | ◻ |
| 24.15-h | Deliverable | Step 7.4 | ◻ |

**Count check:** 67 Deliverable(-seq/split) rows + 5 covered-elsewhere mappings (24.10-j, 24.7-b/c/d, 24.6-s) — matches the mechanical extraction from the seven committed docs (2026-07-03). Excluded-by-verdict items are in Deferred, not here.
