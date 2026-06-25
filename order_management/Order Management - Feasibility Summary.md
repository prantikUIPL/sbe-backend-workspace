# Order Management (Epic 24) — Feasibility Summary

**Source:** `order_management/Order Management - Admin Panel User Stories.md` — Confluence SBE / Admin Panel page `3859742741`, "Story 24 — Order Management" (15 stories 24.1–24.15, Admin role), extracted 2026-06-25.
**Date:** 2026-06-25. **Method:** decompose the 15 stories into 115 atomic sub-requirements → ultracode workflow (6 repo/schema scans + 8 cluster feasibility agents + adversarial re-verification of every non-Deliverable verdict against the source-of-truth schema `admin-backend-api/prisma/schema.prisma`).

**Scope decisions (from the user):** (1) The referenced external sheets (Order Status sheet; Payment Plan Milestone Status Google Sheet) and the 4 referenced Admin Panel epics were **not fetched** — they are recorded in the Cross-Epic Dependencies register. (2) Third-party integrations (HubSpot, QuickBooks, Stripe, Social Tables) were **assessed against the actual repo code**, not assumed external.

> The full analysis (all 7 sheets) lives in **`Order Management - Feasibility Analysis (Consolidated).xlsx`**. This markdown is the narrative companion.

## Bottom line
The epic is **broadly buildable but materially incomplete on the data model.** Of 115 atomic requirements: **39 Deliverable, 55 Partial, 13 Not Deliverable, 8 Needs Clarification.** The core records already exist — `Order` (billing snapshot, fees, salesperson, Stripe + QuickBooks ids, `paid_amount`), `OrderItem` (parent/child add-on tree + product/show links), `OrderAgreement` (signer/sign-date/terms), `Invoice`/`InvoiceLineItem` (with fee line types + QB columns), `PaymentTransaction` (installment ledger), `InventoryReservation` (committed|released), the RBAC graph, append-only audit-log patterns, `ExhibitorSession.impersonated_by` (backs "Log in to Customer Portal"), and a working Word+PDF agreement generator. **But there is no Order Management module today**, and several whole subsystems are missing.

## Primary repo
**admin-backend-api** — net-new Order Management module (no `orders.controller` / order-management module exists). It owns the Prisma migrations / source of truth, so nearly all schema and service work lands here. "Deliverable" means the underlying **data** exists; the admin read/write API + UI still need building.

## Biggest gap clusters (see the "Not Fully Deliverable" sheet)
- **B. Refunds** *(several Not Deliverable)* — no `Refund` model, no `refund_amount`/`refund_reason`/`refund_status` columns, and external-api's Stripe service has `createPaymentIntent`/`Checkout`/`Subscription` but **no `stripe.refunds.create` (0 hits across all repos)**. Blocks all of 24.9 and cancel-with-refund (24.10).
- **C. Manual payment methods** *(Not Deliverable)* — `PaymentTransaction` is hard-wired to Stripe (`NOT NULL stripe_payment_method_id`/`stripe_customer_id`); `PaymentMethod.type` is a free VarChar default `'card'`. No Check/Bank Wire/ACH/PayPal model and no admin mark-Paid/Unpaid path.
- **D. Payment-plan management** — no "Unallocated Balance" concept, no manual-installment add (Stripe NOT NULL + unique idempotency_key block it), no per-installment milestone status, no 60/30-day date rule.
- **E. QuickBooks** *(Not Deliverable)* — **absent in every repo**; only dormant `quickbooks_*` sync-status columns + a "future module" comment.
- **F. HubSpot** — a client exists (contact/company/deal create+update+associate) but **no `updateDeal`/owner setter and no `Order.hubspot_deal_id`** mapping.
- **G. Missing Order-level fields** — single generic `Order.notes` instead of `internal_notes`/`payment_memo`/`invoice_note`(PO)/`additional_terms`; no `additional_emails`; no `assigned_sales_rep_id` (only the creating `sales_person_id`, null for self-service); no `order_source`/`sales_channel`; granular Cancelled statuses not in the `OrderStatus` enum. Most of these **already exist on `Cart`** and must be promoted onto `Order` at placement.
- **H–L.** Order↔Show linkage is per-line only (no order-level show) which complicates the Show column/filter and **Move Show** (no service exists); agreement/invoice generators are **cart-keyed** (need order-keyed + an invoice-PDF renderer); inventory auto-release on cancel has the model but **no cancel-triggered service**; the **payment-reminder cron is absent** (all ingredients present).

## What already exists (de-risks the build)
Stripe charge primitives + webhook (owns paid status), the cart-keyed Word/PDF agreement generator, customer-portal impersonation (24.5-j **Deliverable**), the signer record (24.6-i **Deliverable**), append-only audit logs (24.14-e **Deliverable**), `InventoryReservation` release plumbing, and `Cart` fields (`internal_notes`/`invoice_note`(PO)/`additional_terms`/`assigned_sales_rep`) that supply the order-level data the `Order` entity itself lacks.

## "Centralized billing service"
24.1 & 24.6 say Total / Balance Due / totals come from a "centralized billing service." **No such discrete service exists** — totals are snapshotted on `Order` (`subtotal`/`tax`/`total`/`setup_fees`/`cleaning_fees`/`paid_amount`); Balance Due is derivable as `total − paid_amount`. Same pattern flagged in the Order History epic. This is an architectural decision for the BA (**DEP-1**).

## Repos needing changes (besides admin-backend-api)
| Repo | Why |
|---|---|
| **admin-backend-api** | **Primary** — net-new module + nearly all schema work (refund model, manual-payment enum/columns, order-level fields, status enum, move-show, audit enum, RBAC keys). |
| **external-api-service** | Stripe **refund** primitive (absent), the net-new **QuickBooks** integration, and HubSpot `updateDeal`/owner + Order sync. |
| **background-worker-service** | The **payment-reminder cron** (absent) + overdue handling; optional async HubSpot/QuickBooks sync workers. |
| **exhibitor-backend-api** | Shared portal flows — additional-users invite, customer-portal impersonation / password-reset re-use. |
| **pulse-broker-service** | **Effectively not impacted** — flagged on only 4 items for optional event emission on order-status/sales-rep changes; no schema or core logic lives there. |

## Cross-epic dependencies (out of scope, but they gate us)
12 dependencies in the "Cross-Epic Dependencies" sheet — **5 hard blockers**:

| Dep | Order Management needs | Gated item(s) | Owner |
|---|---|---|---|
| **DEP-2** | A net-new QuickBooks Online integration (auth + client + sync worker) | 24.6-aa QB Force Sync; 24.8-j milestone actions; 24.6-c | external-api-service / integration team |
| **DEP-4** | The "Saved Cart Payment Plan" entity to reference | 24.6-s Payment Plan reference | Cart Management - Saved Cart epic |
| **DEP-7** | Booth Build route + "Booth Build team" role/permission key | 24.5-c Booth Build link | Booth Build Cart/Contract epic |
| **DEP-8** | The **Order Status sheet** (status → actions, editability, HubSpot/QB updates) | 24.6-c/ad/b, 24.10-d | BA (sheet, no link in source) |
| **DEP-9** | The **Payment Plan Milestone Status sheet** (milestone values + QB actions) | 24.8-j, 24.8-c | BA (Google Sheet) |

Architectural/external: **DEP-1** centralized billing service, **DEP-11** Social Tables floorplan auto-release ("subject to confirmation"). Soft: **DEP-3** HubSpot deal sync, **DEP-5** 60/30-day rules (Share Cart), **DEP-6** inventory mechanics (Create Cart/Order), **DEP-10** Upsell/Onsite workflows, **DEP-12** Cart→Order field promotion.

## Open questions
**16 consolidated, prioritized questions** in the "Open Questions for BA" sheet (deduped from ~79 raw) — **6 High priority:** the centralized-billing-service meaning, the refund-model architecture, the QuickBooks build scope, manual-payment modeling (relax Stripe NOT NULL columns?), the order-status model + Order Status sheet, and the payment-plan allocation/milestone + 60/30-day rules.

## Method caveats
Verification was high-precision: of 76 non-Deliverable items, the adversarial pass changed only one (24.1-l Partial→Deliverable) and **6 items could not be independently re-verified** (their verifier agents hit the structured-output retry cap) — these retain their original cluster verdict: 24.1-g, 24.2-b, 24.5-d, 24.6-v, 24.7-a, 24.8-f.
