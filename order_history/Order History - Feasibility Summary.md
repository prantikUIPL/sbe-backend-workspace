# Order History (Epic 13) — Feasibility Summary

**Source:** `SBE - Order History Exhibitor.xlsx` (13.1 Order History page, 13.2 Order Listing Table, 13.3 Order Details Page) **+ `SBE-Exhibitor_Stories-24thJune2026_3:49pm.pdf`** (the 4 referenced stories).
**Date:** 2026-06-24 (revised after referenced stories provided). **Method:** scan of all 5 SBE repos → per-requirement feasibility verdict → adversarial re-verification of every gap against the source-of-truth schema (`admin-backend-api/prisma/schema.prisma`) → reconciliation with the 4 referenced stories.

> The full analysis (all sheets) lives in **`Order History - Feasibility Analysis (Consolidated).xlsx`**. This markdown is the narrative companion.

## Bottom line
The epic is **largely deliverable but not fully** with the current data model. Of 59 atomic requirements: **38 Deliverable, 19 Partial, 1 Not Deliverable, 1 Needs Clarification.** The Order data, line-item typing (booth/add-on/sponsorship/fees), installment rows, coupon/gift-cert/fees snapshots, and agreement acceptance record all exist.

### What the 4 referenced stories changed (full extracts in the "Referenced Stories" sheet of the consolidated xlsx)
- **Booth Upgrade (Epic 7)** — data contract now known (size increase → pay price difference → select booth number → old booth released). "Upgrade details" moved from *Needs Clarification* → *Partial* (storage design needed, not a clarification).
- **Payment Schedule Visibility (19.5)** — the schedule *display* is deliverable from existing installment rows; salesperson *origination* is an admin-epic concern. Moved *Partial* → *Deliverable* for the read-only display.
- **Credit Card Payment Workflow (19.7)** — is **checkout-time** payment; it does **not** define the early-pay flow, so the **Pay-early endpoint gap stands** (early-pay is described only in 13.2).
- **View Onsite Booth Contact (16.1/22.4/22.5)** — stories explicitly want the onsite contact **at the order level**, but the schema keys it `(company_id, show_id)` — **confirmed order-linkage gap** (display-only for this epic; Edit + HubSpot sync belong to epics 16/22).
- **Booth Number** — source identified (Social Tables booth identifier selected at booth selection/upgrade) but still **not persisted** → remains the only **Not Deliverable** item.
- **"Centralized billing/pricing service"** — confirmed a **system-wide** concept (recurs in booth-upgrade & upsell stories), not unique to Order History; no discrete service exists today (pricing is snapshotted on the Order).

## Repos that need changes (besides exhibitor-backend-api)
| Repo | Why |
|---|---|
| **admin-backend-api** | Owns prisma migrations (source of truth). Needed if we add a persisted `Booth Number` column, an `overdue` enum value, or snapshot fields (booth size/type) — and for any salesperson custom payment-schedule origination in the cart. |
| **external-api-service** | Houses Stripe charge primitives + the payment webhook (source of truth for paid status). Needed for the **Pay-early** endpoint (charge an existing order's scheduled installment off-schedule) and to reconcile `paid_amount`. |
| **background-worker-service** | Cron home. Needed only if **Overdue** must be a *persisted* status (an overdue-marking job) rather than derived at read time. |
| **pulse-broker-service** | **Not impacted.** |

> Primary repo is **exhibitor-backend-api** — net-new Order History module (none exists today). "Deliverable" means the *data* exists; the read API + UI still need building.

## Gap themes (see the "Not Fully Deliverable" sheet)
- **A. "Centralized billing service"** — totals/savings exist as snapshots on the Order; no discrete service. Needs BA confirmation (display snapshot vs build/recompute service).
- **B. Booth Number** *(Not Deliverable)* — source known (Social Tables id), not persisted. Needs a column + write path.
- **C. Booth Size / Type** — derivable from `Product.length/width` + `ProductType`, but not snapshotted (drift risk); Standard/Premium/Corner not modeled.
- **D. Booth Upgrade details** — contract known (DEP-2); needs storage design.
- **E. Per-installment "Overdue"** — no `overdue` enum; derive or add enum + cron.
- **F. Order Payment Status derivation** — no `unpaid`/`paid in full` literal; derive from `paid_amount` vs `total` + installment rollups.
- **G. Order → Show link** — `Order` has no `show_id`; shows/city/dates/onsite-contact derived via `OrderItem.show_product_id → ShowProduct → Shows`. Multi-show + non-show order types unhandled.
- **H. Invoice PDF** — no stored PDF; PPL-only renderer exists, must be generalized.
- **I. Pay-early endpoint** — no route to pay an existing order's scheduled installment early.
- **J. Payment schedule display** — deliverable from installment rows (origination = DEP-4).
- **K. Onsite contact** — order-level linkage gap (DEP-3).

## Referenced stories — located in `SBE-Exhibitor_Stories-24thJune2026_3:49pm.pdf`
`Booth Upgrade` (Epic 7, pp.102–105), `Payment Schedule Visibility` (19.5, p.472), `Credit Card Payment Workflow` (19.7, pp.474–475), `View Onsite Booth Contact` (16.1/22.4/22.5, pp.447–448, 500–501). Full extracts in the **"Referenced Stories"** sheet of the consolidated xlsx.

## Remaining open questions
Now **10 focused questions** (down from 32 once the stories were folded in) — 4 High priority: the *centralized billing service* meaning, *order-level onsite contact* vs per-show data, *early-pay method & scope*, and *booth-number persistence*. See the "Open Questions for BA" sheet.

## Cross-epic dependencies (out of scope, but they gate us)
The salesperson schedule origination and the onsite-contact edit/HubSpot sync are confirmed **out of scope** for this epic. Where Order History **cannot proceed** until an out-of-scope epic produces the data, it's recorded in the "Cross-Epic Dependencies" sheet (8 dependencies). The **4 hard blockers**:

| Dep | Order History needs | Gated item | Owner |
|---|---|---|---|
| **DEP-1** | Booth Number persisted (Social Tables id chosen at selection/upgrade) | 13.3 Booth Number *(only Not-Deliverable)* | Buy-flow / Social Tables |
| **DEP-2** | Upgrade record (from/to size, price difference, new booth no.) | 13.3 Upgrade details | Booth Upgrade (Epic 7) |
| **DEP-3** | Order-level onsite contact association | 13.3 Onsite contact | Onboarding (Epic 22) / Edit (Epic 16) |
| **DEP-4** | Salesperson-originated installment rows (dates/amounts/method) | 13.3 Payment schedule display; payment-status derivation | Admin/Salesperson order-build epic |

Soft dependencies (Order History can build a fallback, cleaner once upstream lands): DEP-5 signed-agreement document, DEP-6 invoice-PDF ownership, DEP-8 payment status updates. DEP-7 (centralized billing/pricing service) is an architectural decision.
