---
atom_id: OM-P1
title: Order Management Phase-1 Release (7 stories, ship-together)
version: v1
status: draft
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

# OM-P1 Implementation Plan — Order Management Phase-1 Release (v1 — Draft)

**Scope:** 7 phases on ONE branch, one release. Phase 1: 24.9 Refunds (SBE-1133) · Phase 2: 24.10 Cancellation (SBE-1134) · Phase 3: 24.11 Cancel/Refund Emails (SBE-1135) · Phase 4: 24.8 Payment Plans (SBE-1132) · Phase 5: 24.7 Payments View (SBE-1131) · Phase 6: 24.6 Order Details (SBE-1130) · Phase 7: 24.15 Payment Reminders (SBE-1139).

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

---

## Implementation Order

> Per-phase pattern: build → spec tests green locally → Prantik reviews & commits (`type(SBE-11xx):` scope) → next phase. Pushes + pipeline checks batched at Prantik's discretion. Every step's full field-level spec = the story doc rows named in the step.

### Phase 1 — 24.9 Refund Management (SBE-1133) — U1, U2, U3

| Step | What | Spec rows |
|---|---|---|
| 1.1 | Migration: `refunds` ledger table (per-installment rows: pt_id FK, amount, method stripe|manual, reason/memo, actor, stripe_refund_id nullable, status) + `refund_failed` → PaymentTransactionStatus + `orders.refund` permission seed | 24.9-a…e, doc D1 |
| 1.2 | external-api: internal Stripe refund wrapper (stripe.refunds.create; idempotency key; maps Stripe errors) | 24.9-d/e, doc D2 leg |
| 1.3 | external-api: handleChargeRefunded rework — amount-aware, ledger-consistent (partial refunds recognized; PT → refunded only at full; refund_failed on failure path) | 24.9 D2 |
| 1.4 | admin: `POST /orders/:id/refunds` — per-installment selection (primitive) + order-level composition; eligibility: Stripe option iff `stripe_charge_id` present, Manual always (delivers 24.9-f both halves — manual rows never have charge ids, so Manual-only auto-materializes when Phase 4 creates them); validation caps vs paid/ledger; audit | 24.9-a…h |
| 1.5 | Derivations: OrderStatus.refunded / balance figures remain DERIVED (gross paid_amount − ledger) — helper in orders module | 24.9 D1/D3, U3, U20 |
| **Gate** | Refund a seeded card order end-to-end against Stripe test mode: ledger row, PT transition, webhook reconciliation; spec tests green | |

### Phase 2 — 24.10 Order Cancellation (SBE-1134) — U4, U5

| Step | What | Spec rows |
|---|---|---|
| 2.1 | admin: `POST /orders/:id/cancel` two-phase (`?confirm=` preview → confirm): tx = status→canceled + PT cascade (scheduled→canceled, `next_retry_at:null`, widened where) + optional refund composition via Phase-1 service (never re-implemented) + audit; `orders.cancel` seed | 24.10-a…i, j→U1 |
| 2.2 | admin: `InventoryService.releaseForOrder(orderId, tx)` (committed→released updateMany, `cart_id != null` guard) called in the cancel tx | 24.10-k |
| **Gate** | Cancel paths (never-paid / no-refund / partial / full) leave consistent PT + inventory + ledger state in one tx; spec tests green | |

### Phase 3 — 24.11 Cancel/Refund Emails (SBE-1135) — U6

| Step | What | Spec rows |
|---|---|---|
| 3.1 | Seeders: `order_canceled` + `order_refunded` trigger slugs + EMAIL templates (append-only; META guard passes) | 24.11-c, D1/D2 |
| 3.2 | admin: notification service — recipient chain (billing_email → company contact → skip+log), POST-COMMIT dispatch via admin mailer (non-throwing pattern), one-email-per-action (cancel sends order_canceled w/ optional refund tokens; standalone refund sends order_refunded; never both) | 24.11-a…e, D1/D3 |
| 3.3 | Wire `send_email` boolean (default true) into Phase-1/2 DTOs; backend-enforced | 24.11-a/b/d/e |
| **Gate** | Flag on/off matrix verified: exactly one email per action, correct template + recipients, no email on unchecked; spec tests green | |

### Phase 4 — 24.8 Payment Plan Management (SBE-1132) — U7–U12

| Step | What | Spec rows |
|---|---|---|
| 4.1 | Migration: `payment_type` (CartPaymentMethod reuse; backfill credit_card; NOT NULL, no default; doc-comments on enum + column) + `payment_memo` (nullable) + stripe_pm/cus nullable w/ why-comments + `admin_manual` source value; mirrors to 4 repos (db push) | 24.8-a/b, D2/D3/D4 |
| 4.2 | 5 PT-writer updates: add `payment_type: credit_card` at the verified card-flow creation sites (exh payments/cart/ppl-checkout, ext webhook, admin ppl) | 24.8 D2 |
| 4.3 | worker: charge + retry cron guards `payment_type = credit_card` | 24.8 D3, U9 |
| 4.4 | admin: C13 mapper (PT → installment rows: D1 label map, amounts, dates, invoice #, payment_type, payment_memo) as a shared orders-module helper — single home, consumed by Phases 5/6 | 24.8-e…h, U10 |
| 4.5 | admin: plan routes — plan view + scheduled-only installment edit/delete + `PATCH :id/payment-plan/installments/:installmentId` Mark-as-Paid/Unpaid (manual-method-only gate; Paid→succeeded+paid_at+money writes mirroring webhook; Unpaid→scheduled+reversal — the one legit gross decrement); plan-level lock `paid_in_full_at`; in-tx derived unallocated; null-show-date skip+warn; UUID idempotency; two-phase confirm (shared-base hoist if reusing cart's confirm helper — P-D8); `orders.payment-plan.*` seeds; audit | 24.8-c/d/i/j/k/m + l-display |
| **Gate** | Manual lifecycle end-to-end: create manual installment → appears Unpaid → Mark-as-Paid → money/status verified → Unpaid reversal verified; crons ignore manual rows; spec tests green | |

### Phase 5 — 24.7 Payments View (SBE-1131) — U13

| Step | What | Spec rows |
|---|---|---|
| 5.1 | admin: `GET /orders/:id/payments` = U10 rows + order money summary + derived Paid/Unpaid label (native implementation of `deriveOrderPaymentStatus` semantics — P-D8); `orders.payments.read` seed; Swagger (FE reads method enum from DTOs) | 24.7-a/e (b/c/d delivered by 4.5) |
| **Gate** | Route returns correct rows/labels for card, manual, refunded, voided fixtures; spec tests green | |

### Phase 6 — 24.6 Order Details (SBE-1130) — U14–U18

| Step | What | Spec rows |
|---|---|---|
| 6.1 | Migration: `Order.additional_emails` Json + permission seeds (`orders.view/update/sales_rep.update/payments.void`) | 24.6-i/y |
| 6.2 | admin: derivation helpers — `status_display` (D1 six-value map over status + ledger arithmetic) + rep/source chain (D3) — native, shared within orders module | 24.6-b/j/t |
| 6.3 | admin: `GET /orders/:id` aggregate — general, notes/memo/terms (read-only; `Order.notes` NEVER exposed), billing, additional_emails, customer link, line-item tree w/ flat fallback + `cart.coupon.code` join, onsite-contact ABSENT (deferred), fees, totals + items-subtotal/fees breakdown (C10), plan block via U10 + next-installment query, signer, agreement/payments links, sales rep object | 24.6-a,c…h,k,l,m,n,o,p,q,s-link |
| 6.4 | admin: `PATCH /orders/:id` (billing + additional_emails; 24.6-aa status matrix from Status Breakdowns; audit) + `PATCH :id/sales-rep` (deal-owner-pattern validation → sales_person_id; dropdown source decision: reuse `GET carts/deal-owners` if cleanly consumable, else own endpoint) | 24.6-h/i/u/aa |
| 6.5 | admin: `POST /orders/:id/payments/:transactionId/void` — guard status IN (scheduled, failed) → canceled + next_retry_at:null; "Voided" label via U10; audit | 24.6-z void half (refund half = flags wired to Phase 1) |
| **Gate** | Aggregate correct for: exhibitor-created (full billing, tree), admin-created (null billing, flat — graceful), multi-show, subscription (no cart), refunded, cancelled fixtures; edit matrix blocks per status; void end-to-end; spec tests green | |

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
