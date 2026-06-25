# Order History (Epic 13) — Feasibility Summary

**Source:** `SBE - Order History Exhibitor.xlsx` (13.1 Order History page, 13.2 Order Listing Table, 13.3 Order Details Page) **+ `SBE-Exhibitor_Stories-24thJune2026_3:49pm.pdf`** (the 4 referenced stories).
**Date:** 2026-06-24 (initial); **RE-AUDITED 2026-06-25** under the *built-write-path lens*. **Method:** scan of all 5 SBE repos → per-requirement feasibility verdict → adversarial re-verification of every gap against the source-of-truth schema (`admin-backend-api/prisma/schema.prisma`) → reconciliation with the 4 referenced stories → **2026-06-25 producer re-audit**: for every requirement, trace the actual `.create`/`.update` write-path that produces the data, since the project is mid-development and a schema field existing is **not** proof the data is produced.

> The full analysis (all sheets) lives in **`Order History - Feasibility Analysis (Consolidated).xlsx`**. This markdown is the narrative companion.

## Bottom line
Re-audited under the built-write-path lens (a schema column existing is **not** enough — a working producer must write the data today, else it is **Blocked** until the upstream feature ships, or **Not Deliverable** if no path exists even in principle). Of 59 atomic requirements: **40 Deliverable, 13 Partial, 5 Blocked, 1 Not Deliverable** (Needs Clarification → 0).

**The lens's headline finding — 5 BLOCKED items whose schema columns exist but nothing writes them yet:**
- **Onsite contact (#36)** — `OnsiteBoothContact` table exists (migration) but **zero** code writes it; producer = the unbuilt *Exhibitor Onboarding → Onsite Booth Contacts* step.
- **Gift Certificate line (#46)** — **no** `giftCertificateRedeem.create` anywhere (only admin read-reports); the redemption flow is unbuilt.
- **Salesperson payment schedule (#56)** — admin/staff checkout writes **zero** `PaymentTransaction` rows; only exhibitor self-service produces a *system* equal-split (fixed 30-day cadence). No salesperson-set method/schedule producer.
- **Booth Number (#26)** and **Booth Upgrade details (#33)** — reclassified Not-Deliverable → **Blocked**: planned upstream features (Social Tables buy-flow / Epic 7) that aren't built, rather than concepts that can never exist.

> **Early-pay (#10, #13) is Partial, not Blocked** (independently re-verified 2026-06-25): a "pay next scheduled installment now" endpoint is buildable on **already-produced** primitives — scheduled `PaymentTransaction` rows already carry a saved card + `due_date`, plus the off-session charge primitive, webhook reconciliation, and `paid_in_full` gating. Only the spec's *"salesperson-set payment method / schedule"* wording is unbuilt (that's the separate Blocked item #56 / DEP-4) — **⚑ BA flag** retained on that wording.

**What *improved* once real producers were located:** Invoice download (#9/#12/#35), order/header Payment Status (#5/#30), Associated Shows (#7), Booth Size (#31) → **Deliverable** — e.g. the charge-success webhook **does** create `Invoice` + a cart-flow `InvoiceLineItem` tree for booth orders (`webhook.service.ts:2048/2072`), which the first pass missed.

**What dropped to Partial (partial producer coverage):** the booth/add-on/sponsorship discriminator (#43, only the cart path writes `cart_item_type`), the coupon line (#45, `coupon_code` vs `coupon_amount` split across paths), conditional summary lines & field-backing (#50/#52, `tax` hardcoded 0 + gift-cert unproduced), and per-installment Overdue (#11, *Overdue* is a derived state, not a produced status).

### What the 4 referenced stories changed (full extracts in the "Referenced Stories" sheet of the consolidated xlsx)
- **Booth Upgrade (Epic 7)** — data contract now known (size increase → pay price difference → select booth number → old booth released). **Epic 7 is unbuilt (verified 2026-06-25 — no upgrade producer anywhere in the codebase), so "Upgrade details" is *Blocked*** (re-audit reclassified Not-Deliverable → Blocked: a planned upstream feature, not a never-possible concept). Becomes Deliverable once Epic 7 ships. DEP-2.
- **Payment Schedule Visibility (19.5)** — read-only display of the **system** schedule is deliverable from existing installment rows, **but** the schedule "set by salesperson" (#56) is **Blocked** — admin/staff checkout writes **zero** `PaymentTransaction` rows; only exhibitor self-service produces a system equal-split. DEP-4.
- **Credit Card Payment Workflow (19.7)** — is **checkout-time** payment; it does **not** define the early-pay flow. Early-pay (#10/#13) is **Partial**: the pay-existing-installment endpoint is net-new but buildable on produced primitives (scheduled `PaymentTransaction` + saved card + off-session charge + webhook); only the *"salesperson-set method/schedule"* wording is unbuilt (→ DEP-4, BA flag).
- **View Onsite Booth Contact (16.1/22.4/22.5)** — the per-show display **decision stands** (follow the schema, one contact per show, not the epics-16/22 order-level framing). **BUT re-audit 2026-06-25 → now *Blocked*:** `OnsiteBoothContact` has **no write-path anywhere** in the 5 repos — its producer is the unbuilt *Exhibitor Onboarding → Onsite Booth Contacts* step. There is no produced data to display until that step ships. DEP-3 **reopened** as a producer blocker.
- **Booth Number** — source identified (Social Tables booth identifier selected at booth selection/upgrade) but still **not persisted by any flow** → **Blocked** (re-audit reclassified Not-Deliverable → Blocked: planned buy-flow producer, unbuilt). DEP-1.
- **"Centralized billing/pricing service"** — confirmed a **system-wide** concept (recurs in booth-upgrade & upsell stories), not unique to Order History; no discrete service exists today (pricing is snapshotted on the Order).

## Repos that need changes (besides exhibitor-backend-api)
| Repo | Why |
|---|---|
| **admin-backend-api** | Owns prisma migrations (source of truth). Needed if we add a persisted `Booth Number` column, an `overdue` enum value, or snapshot fields (booth size/type) — and for any salesperson custom payment-schedule origination in the cart. |
| **external-api-service** | Houses Stripe charge primitives + the payment webhook (source of truth for paid status). Needed for the **Pay-early** endpoint (charge an existing order's scheduled installment off-schedule) and to reconcile `paid_amount`. |
| **background-worker-service** | Cron home. Needed only if **Overdue** must be a *persisted* status (an overdue-marking job) rather than derived at read time. |
| **pulse-broker-service** | **Not impacted.** |

> Primary repo is **exhibitor-backend-api** — net-new Order History module (none exists today). Under the re-audit lens, **"Deliverable" means the data is *produced* by a built write-path today**; the read API + UI still need building. **"Blocked"** means the schema may have the column but no code writes it yet (upstream feature unbuilt).

## Gap themes (see the "Not Fully Deliverable" sheet)
- **A. "Centralized billing service"** — **Total Saving (13.3)** and **Total Amount (13.2)** are both **produced** today: `CartPricingService` (admin + exhibitor) **is** the centralized engine ("single source of truth for all cart money") and freezes `total`/`total_savings` onto the Order at checkout. Display the snapshot. Residual = a BA wording question (snapshot vs live recompute) — OQ1; Total Amount moved *Needs Clarification → Partial*.
- **B. Booth Number** *(Blocked)* — no column and **no producer**; the Social Tables id chosen in the (planned, unbuilt) booth-selection/upgrade buy-flow would populate it. DEP-1.
- **C. Booth Size / Type** — **Size** *(Deliverable — re-audit)*: `Product.length/width` are written by product-management and required for booth families; join+format `LxW` (minor live-read/snapshot caveat). **Type (Standard/Premium/Corner)** *(Not Deliverable)*: taxonomy does not exist anywhere — no `booth_type`/tier column, ProductType "Booth" has only `Booth`/`Workshop Pavilion` *families*, zero Premium/Corner, no geometry for Corner. The one true "no path even in principle" item.
- **D. Booth Upgrade details** *(Blocked)* — Epic 7 unbuilt; no upgrade producer exists (DEP-2). Planned feature → Blocked, not Not-Deliverable.
- **E. Per-installment "Overdue"** *(Partial — re-audit corrected)*: "Overdue" is **not a produced status** — no enum value, no write-path sets one; a past-due installment stays `scheduled` and the daily cron will actually *attempt to charge it* (scheduled→processing→succeeded/failed). It is a derived state with real lifecycle caveats, so *Partial*, not Deliverable.
- **F. Order Payment Status derivation** *(Deliverable — re-audit)*: `Order.status`/`paid_amount`/`paid_in_full_at` are produced end-to-end (checkout + webhook `computeNewOrderStatus`); the 3-value badge is a mechanical read rollup. **⚠ refund blind spot persists** (see open questions).
- **G. Order → Show link** *(Partial)*: `Order` has no `show_id`; Associated-Shows/city/dates derived via `OrderItem.show_product_id → ShowProduct → Shows` (the id **is** produced at checkout, so Associated Shows #7 is now Deliverable; the header derivations #27/#28/#29 stay Partial for non-show types + multi-show ambiguity).
- **H. Invoice PDF** *(Deliverable — re-audit)*: the charge-success webhook **does produce** `Invoice` + a cart-flow `InvoiceLineItem` tree for booth/product orders (`webhook.service.ts:2048/2072`). Remaining work = generalize the PPL-only pdfkit renderer + add a download route. Caveat: invoice exists only after a successful installment (one per installment in split mode).
- **I. Pay-early endpoint** *(Partial)* — no route to pay an existing order's installment early, but it's buildable **today** on produced primitives (scheduled `PaymentTransaction` + saved card + off-session charge + webhook + paid-in-full fields). Caveat (⚑ BA flag): the spec's *"salesperson-set payment method / schedule"* doesn't exist (the card is the exhibitor's own; schedule is a fixed 30-day system cadence) — that origination model is the separate Blocked item #56 / DEP-4.
- **J. Salesperson payment schedule** *(Blocked)* — admin writes no `PaymentTransaction` rows; only system equal-split exists. Read-only display of the *system* schedule is deliverable, but the salesperson-origination this req names is unbuilt. DEP-4.
- **K. Onsite contact** *(Blocked — re-audit corrected)*: per-show display decision stands, but `OnsiteBoothContact` has **no producer** (unbuilt onboarding step). DEP-3 reopened.
- **L. Line-item type discriminator** *(Partial)* — `cart_item_type` written only by the cart checkout path; admin/payments/PPL paths leave it null.
- **M. Coupon / fee coverage** *(Partial)* — `coupon_code` vs `coupon_amount` split across paths; setup/cleaning fees only on product-cart + admin; `tax` hardcoded 0 (Phase-2 TODO).
- **N. Gift-cert redemption** *(Blocked)* — no `giftCertificateRedeem.create` anywhere; redemption flow unbuilt. DEP-9.

## Referenced stories — located in `SBE-Exhibitor_Stories-24thJune2026_3:49pm.pdf`
`Booth Upgrade` (Epic 7, pp.102–105), `Payment Schedule Visibility` (19.5, p.472), `Credit Card Payment Workflow` (19.7, pp.474–475), `View Onsite Booth Contact` (16.1/22.4/22.5, pp.447–448, 500–501). Full extracts in the **"Referenced Stories"** sheet of the consolidated xlsx.

## Remaining open questions
**9 questions, 7 open** (OQ2 *order-level onsite contact* and OQ5 *overdue + payment-status labels* both **resolved 2026-06-25**). The booth-upgrade-representation question was **removed** — an Epic 7 design concern, out of scope. 3 High priority remain: the *centralized billing service* / Total Amount meaning, *early-pay method & scope*, and *booth-number persistence*. **OQ5 resolution:** use the 3-value order-level set (Paid in Full / Partially Paid / Unpaid) computed at runtime as a derived value (not a DB enum); Overdue is per-plan and rolls up (no separate badge) — **⚑ one BA wording-flag retained**: the 13.2 listing-row "(Paid, Unpaid)" shorthand should match the canonical 3-value derived status. **⚠ Code caveat:** `OrderStatus.refunded` is never assigned (the `charge.refunded` webhook only flips the `PaymentTransaction` + voids the `Invoice`), so refunds are invisible at the order level — if the badge must reflect them, derive from `PaymentTransaction.refunded`/`Invoice.void`, not `OrderStatus`. See the "Open Questions for BA" sheet (carries a **Status / Resolution** column).

## Cross-epic dependencies (out of scope, but they gate us)
The built-write-path re-audit turned the cross-epic story into the **5 BLOCKED items** — each waits on an upstream feature that produces no data yet (plus early-pay #10/#13, which is *Partial* but whose salesperson-set-method framing also leans on DEP-4). Recorded in the "Cross-Epic Dependencies" sheet (now 9 dependencies). The **hard producer-blockers**:

| Dep | Order History needs (producer that doesn't exist yet) | Gated item(s) | Owner |
|---|---|---|---|
| **DEP-1** | Booth Number persisted (Social Tables id chosen at selection/upgrade) | 13.3 Booth Number #26 *(Blocked)* | Buy-flow / Social Tables |
| **DEP-2** | Upgrade record (from/to size, price difference, new booth no.) — **Epic 7 unbuilt** | 13.3 Upgrade details #33 *(Blocked)* | Booth Upgrade (Epic 7) |
| **DEP-3** | A built write-path for `OnsiteBoothContact` (the onboarding step that populates it) | 13.3 Onsite contact #36 *(Blocked)* | Exhibitor Onboarding epic (16/22) |
| **DEP-4** | Salesperson-originated installment rows (dates/amounts/method) | 13.3 schedule #56 *(Blocked)*; also the salesperson-set-method framing of early-pay #10/#13 *(Partial — buildable now on the exhibitor's own card)* | Admin/Salesperson order-build epic |
| **DEP-9** | A gift-certificate redemption flow that writes `GiftCertificateRedeem` | 13.3 Gift Certificate line #46 *(Blocked)* | Checkout / Gift-cert epic |

> **DEP-3 reopened 2026-06-25 (producer grounds).** The per-show display *decision* still stands (read `OnsiteBoothContact (company_id, show_id)` per booked show, not the epics-16/22 order-level framing). But the re-audit found **nothing writes that table** — its producer is the unbuilt onboarding step — so there is no produced data to show. This is a data-production blocker, distinct from the earlier order-level-framing question. Edit + HubSpot sync remain epic 16/22 scope.

Soft dependencies (Order History can build a fallback, cleaner once upstream lands): DEP-5 signed-agreement document, DEP-6 invoice-PDF ownership, DEP-8 payment status updates. DEP-7 (centralized billing/pricing service) is an architectural decision.
