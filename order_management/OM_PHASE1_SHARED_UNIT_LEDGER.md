# OM Phase-1 Release — Shared-Unit Allocation Ledger

**Created:** 2026-07-03, at completion of the 7-story Step-1 hard gate (all scopes locked with Prantik; per-story docs committed d2d4b98 · 156b9e5 · c230730 · 17578f3 · f0d9864 · fce7b74 · a782d37).

**Release model:** 24.9, 24.10, 24.11, 24.8, 24.7, 24.6, 24.15 ship together as ONE release. **Build order = that sequence.** Every shared unit below is owned by exactly one story; consumers reuse, never rebuild. The 7 implementation plans are written against this ledger — a plan that builds a unit it doesn't own is wrong by definition.

**Jira:** 24.9=SBE-1133 · 24.10=SBE-1134 · 24.11=SBE-1135 · 24.8=SBE-1132 · 24.7=SBE-1131 · 24.6=SBE-1130 · 24.15=SBE-1139 (epic SBE-1078). Shipped context: 24.1-24.4 (SBE-1125), 24.14 (SBE-1138), 24.5 (SBE-1129, merged to dev 2026-07-03 PR#521).

---

## Unit allocations

| # | Unit | Owner | What it is | Consumers (reuse only) |
|---|---|---|---|---|
| U1 | **Refund primitive + ledger** | **24.9** | `POST /orders/:id/refunds` (per-installment selection = the primitive; order-level = composition) + `GET /orders/:id/refund-options` (eligibility read, `orders.refund.read`); `refund_failed` added to PaymentTransactionStatus; refund ledger rows; validation caps; `orders.refund` + `orders.refund.read` permission keys | 24.10 (cancel-with-refund composes it), 24.11 (refund send fires from it), 24.6 (REFUND action flags wire to it; `status_display` Cancelled-qualifiers + Balance = arithmetic over its ledger), 24.7 (refunded rows appear in payments view) |
| U2 | **Amount-aware `charge.refunded` webhook handler** | **24.9** (cross-repo: external-api) | Replaces the amount-blind handler; partial-refund aware; ledger-consistent | Everything reading refund state |
| U3 | **`Order.paid_amount` stays GROSS; `balance_due` is NET everywhere** | **24.9 (D3, decision not code)** | `paid_amount` stays gross; net = derived (gross − refund ledger); sole legit gross decrement = 24.8's Unpaid-reversal. **CANONICAL (audit ruling 2026-07-05): `balance_due` = `total − netPaid` on EVERY order surface** — 24.6-o is authoritative (only story specifying a refund-aware balance); 24.1 mandates "Balance Due sourced from the centralized billing service"; 24.7/24.8 specs are silent on net-vs-gross. **Audit P1:** 24.7 payments (`order-payments.service.ts:66`), 24.8 plan-GET (`order-payment-plan.service.ts:211`), order list (`orders.service.ts:184`) shipped `balance_due` off GROSS — **fix pending** to align all three to net (24.6 already nets at `order-details.service.ts:244`). | 24.6-o Balance (net), 24.7 money summary (→ net), 24.8 plan-GET (→ net), 24.1 order-list Balance Due (→ net) |
| U4 | **Cancel endpoint + PT cascade** | **24.10** | Order cancel w/ two-phase `?confirm=`; cascade: scheduled→`canceled` + `next_retry_at:null` (widened where); `orders.cancel` key | 24.11 (post-commit dispatch), 24.6 (Cancelled display + editability gating), 24.15 (canceled rows drop from selection) |
| U5 | **Inventory `releaseForOrder`** | **24.10 (row k)** | Release order items' inventory on cancel (absorbed from OOS 24.12 as integrity invariant) | — |
| U6 | **Cancel/refund email pair** | **24.11** | Slugs `order_canceled` / `order_refunded` + templates (SELF-SEEDED per ownership rule); ONE-EMAIL-PER-ACTION; recipient chain billing_email → company contact → skip+log; post-commit dispatch | 24.9/24.10 flows trigger them; 24.6 sheet-findings (departments@ internal notify, send-toggle) = OQ-6 BA rows, NOT scope |
| U7 | **`payment_type` on PaymentTransaction** | **24.8 (D2)** | CartPaymentMethod reuse; backfill `credit_card` NOT NULL, no default; doc-comments on enum + column (credit_card = Stripe = sole non-manual); 5 writer updates in-release | 24.7-a classification, 24.6 method labels, 24.15 predicates (`!= credit_card`), worker guards (U9) |
| U8 | **`payment_memo` on PaymentTransaction** | **24.8** | Nullable; per-installment check-#/wire-ref; distinct from `Order.payment_memo` (24.14's) — name-collision BA note | 24.7-e display, 24.6 plan block |
| U9 | **Worker cron guards** | **24.8 (D3)** | `payment_type = credit_card` added to charge + retry cron predicates; stripe_pm/cus nullable w/ why-comments | 24.15's predicate is the disjoint complement — no double-touch by construction |
| U10 | **C13 PT→installment-row mapper** | **24.8** | Rows: status label (D1 map: succeeded→Paid, scheduled→Unpaid, failed→CC Failed, canceled→Voided, refunded→Refunded), amounts, dates, invoice #, payment_type, payment_memo | 24.7-e (`GET :id/payments`), 24.6-p/q (plan block), NOT 24.15 (direct query) |
| U11 | **Installment PATCH (Mark Paid/Unpaid)** | **24.8** | `PATCH :id/payment-plan/installments/:installmentId`; manual-method-only gate (= 24.7-b, built here); Paid→succeeded + paid_at + webhook-mirroring money writes; Unpaid→scheduled + reversal; audit; `orders.payment-plan.*` keys; `admin_manual` source (D4) | 24.7-b/c/d (delivered here), 24.15-e/f stop signal |
| U12 | **Plan-level CRUD + locks** | **24.8** | Scheduled-only edit/delete; plan lock = `paid_in_full_at`; in-tx derived unallocated; null-show-date skip+warn; UUID idempotency; two-phase confirm port | 24.6 plan display honors the same states |
| U13 | **`GET /orders/:id/payments`** | **24.7** | The story's whole build: U10 rows + order money summary + derived Paid/Unpaid label (`deriveOrderPaymentStatus` port); `orders.payments.read` key. Order-level `PATCH :id/payment-status` DROPPED (24.7-D3) — not owned by anyone | 24.6 links to it; FE dropdown = enum via Swagger |
| U14 | **`GET /orders/:id` detail aggregate** | **24.6** | The page: general/billing/items tree (flat fallback)/coupon join/fees/totals breakdown (C10 residual)/plan block (U10)/signer/rep-source derivation (D3 chain)/`status_display` (D1) | — |
| U15 | **`PATCH /orders/:id`** | **24.6** | Billing edit + `additional_emails` edit; status-gated (24.6-aa matrix from Status Breakdowns tab); audited | — |
| U16 | **`PATCH :id/sales-rep`** | **24.6** | Reassignment → `sales_person_id` (cart deal-owner pattern); NO HubSpot side-effect (OQ-5) | — |
| U17 | **Per-installment VOID endpoint** | **24.6 (D-z, gate decision)** | `POST :id/payments/:transactionId/void`; guard `status IN (scheduled, failed)`; → `canceled` + `next_retry_at:null` (U4's write shape); `orders.payments.void` key. Distinct from U11's delete and U4's cascade | 24.15 stop coverage (settled-set check) |
| U18 | **`Order.additional_emails` (Json)** | **24.6 (D5)** | String-array column + PATCH edit + DTO validation | Conditional CC consumers pending consolidated OQ: 24.6-r, 24.11, 24.15, 24.5 — one-line append each IF BA ratifies |
| U19 | **Reminder cron + templates + settings** | **24.15** | Independent worker cron (clone payment-charge pair); slugs `payment_reminder_upcoming`/`overdue` (SELF-SEEDED); `payment_reminder_{upcoming_days,overdue_interval_days,hour_utc}` = 7/7/14 pending BA **with gate-provenance doc-comments (user directive)**; notification_logs dedupe; dev-only manual trigger | Scheduling-system hand-off note → scheduling register (OQ-4) |
| U20 | **Status display derivations** | **24.6 (D1) owns `status_display`; 24.15 mirrors `deriveIsOverdue`; 24.7 ports `deriveOrderPaymentStatus`** | All pure reads — no story stores any derived state | Shared LABEL MAP lives with U10 (24.8) — single source |

## Permission-key allocation (seeder rows land with their owner's migration/seed)

| Key | Owner |
|---|---|
| `orders.refund` | 24.9 |
| `orders.refund.read` (refund-options eligibility) | 24.9 |
| `orders.cancel` | 24.10 |
| `orders.payment-plan.*` (read/create/update/delete per 24.8 routes) | 24.8 |
| `orders.payments.read` | 24.7 |
| `orders.view`, `orders.update`, `orders.sales_rep.update`, `orders.payments.void` | 24.6 |
| (none — UI-less) | 24.15 |

## Cross-cutting build rules (bind all 7 plans)

1. **Migrations**: admin-backend-api owns all; other repos `db push` mirrors. Int PKs, NOT NULL + backfill preferred (standing prefs). Enum/column doc-comments as locked (U7, U9, U19).
2. **Mailer split**: admin-triggered action emails → admin `MailerService.sendFromTemplate` (mailer.service.ts:192); cron legs → worker mailer (:88). Both write notification_logs; keep `notification_type` consistent.
3. **Template ownership**: each flow seeds its own slugs/templates (24.11: U6; 24.15: U19); E&S epic manages after. Append-don't-reorder in both seeders; fail-loud META guard is the backstop.
4. **NO copying, importing, or replicating functionality** (user directive 2026-07-03; SonarQube duplication gate — precedent `adeba9f` SBE-1129, where the ~1k-line agreement-service copy was refactored into `base-agreement-document.service.ts`). **Same repo:** when needed logic already exists in another module, hoist it into a shared base/common service and make both call sites consume it — never a second copy. **Cross-repo** (e.g. exhibitor 13.3 helpers needed in admin): implement natively to the same *semantics* (the story docs' cited exhibitor code is the behavioral spec, not a source to transplant) — small, repo-idiomatic functions so Sonar's duplication detector has nothing to flag.
5. **No story touches other teams' modules**: cart-module write gaps = register rows (24.6 OQ-1); SonarQube read-only; id-encryption conventions (PR#455) checked at plan time for all new route params.
6. **Parked/deferred — NO plan includes**: 24.6-r send-email (OQ-4), 24.6-v/x HubSpot (OQ-5), 24.6-w QB (epic 65), chargeback trio (24.8-l ND). _(24.6-l2 onsite contact was here — delivered 2026-07-06 as a follow-up once SBE-1169/1171 reached DEV DONE, PR#542; twin 13.3-w PR#305.)_
7. **Registers**: scheduling hand-off → scheduling register only; nothing written to EMAIL_SMS_KNOWN_ISSUES.md (separation rule).

## Sequencing skeleton

```
24.9  U1-U3   refund stack                        (needs nothing)
24.10 U4-U5   cancel + cascade + inventory        (composes U1)
24.11 U6      email pair                          (fires from U1/U4)
24.8  U7-U12  payment-plan stack                  (guards, mapper, PATCH)
24.7  U13     payments view                       (consumes U10)
24.6  U14-U18 detail page + void                  (consumes U1, U4, U10; links U13)
24.15 U19     reminders                           (consumes U7, U11-signal, U17-signal; builds LAST)
```

## Process notes (Step-8 register)

- **Inline the ledger's exact spec into each consuming build brief — don't reference a sibling story's decision by name.** Root cause of the U10 milestone-label drift: the Phase-4 (24.8) build brief said "map the 7 statuses to a display label, display-only **per D1**, no chargeback values" but did NOT inline D1's exact strings (`scheduled→Unpaid, failed→CC Failed, canceled→Voided`) — those live in the 24.6 doc + U10 here, not the 24.8 doc. The build agent filled the gap with the enum's literal names (`Scheduled/Failed/Canceled`), which satisfied the letter of the brief and passed 24.8/24.7 review + smoke (neither pinned the wording). It surfaced only at the Phase-6 (24.6) build, whose brief DID inline the exact map — so that build caught the shipped mapper's deviation and flagged it instead of forking. Fix applied 2026-07-04: relabelled `MILESTONE_STATUS_LABELS` to the U10 map (corrects 24.7/24.8's already-merged displays too; ships with 24.6). Lesson: when a build consumes a shared unit whose canonical spec lives here, paste the spec verbatim into the brief.
