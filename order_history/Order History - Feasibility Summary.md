# Order History (Epic 13) — Feasibility Summary

**Source:** `SBE - Order History Exhibitor.xlsx` (stories 13.1 Order History page, 13.2 Order Listing Table, 13.3 Order Details Page).
**Date:** 2026-06-24. **Method:** scan of all 5 SBE repos → per-requirement feasibility verdict → adversarial re-verification of every gap against the source-of-truth schema (`admin-backend-api/prisma/schema.prisma`).

## Bottom line
The epic is **largely deliverable but not fully** with the current data model. Of 59 atomic requirements assessed: **37 Deliverable, 19 Partial, 1 Not Deliverable, 2 Need Clarification.** The Order data, line-item typing (booth/add-on/sponsorship/fees), installment rows, coupon/gift-cert/fees snapshots, and agreement acceptance record all exist. The shortfalls cluster into a handful of themes, and **4 referenced stories are missing from this file**, which gates several Order Details sections.

> Note: **exhibitor-backend-api has no Order/Order-History module today** (only cart, payments, payment-method, agreement, shows) — the read-side feature is net-new. "Deliverable" means the *data* exists; the API + UI still need building.

## Repos that need changes (besides exhibitor-backend-api)
| Repo | Why |
|---|---|
| **admin-backend-api** | Owns prisma migrations (source of truth). Needed if we add a persisted `Booth Number` column, an `overdue` enum value, or snapshot fields (booth size/type) — and for any salesperson custom payment-schedule origination in the cart. |
| **external-api-service** | Houses Stripe charge primitives + the payment webhook (source of truth for paid status). Needed for the **Pay-early** endpoint (charge an existing order's scheduled installment off-schedule) and to reconcile `paid_amount`. |
| **background-worker-service** | Cron home. Needed only if **Overdue** must be a *persisted* status (an overdue-marking job) rather than derived at read time. |
| **pulse-broker-service** | **Not impacted.** |

## What cannot be delivered fully (themes — see the "Items Not Fully Deliverable" xlsx for the per-row detail)
- **A. "Centralized billing service"** — the brief says Total Amount / Total Saving come from a *centralized billing service*; no such service exists. Values **are** snapshotted on `Order.total` / `Order.total_savings` at checkout. → needs BA confirmation (display snapshot vs build/recompute service).
- **B. Booth Number** *(Not Deliverable)* — no `booth_number` field or source anywhere; `OrderItem` has no metadata column. Needs a new column + a population path, or an external assignment source.
- **C. Booth Size / Type** — derivable from `Product.length/width` and `ProductType`, but **not snapshotted on the order** (drift risk if the product is later edited); "Standard/Premium/Corner" taxonomy isn't modeled/seeded.
- **D. Booth Upgrade details** — depends on the missing **Booth Upgrade** story; no upgrade display fields modeled.
- **E. Per-installment "Overdue"** — `PaymentTransactionStatus` has no `overdue` value. Derive (`scheduled/failed` AND `due_date < now`) or add enum + cron.
- **F. Order Payment Status derivation** — `OrderStatus` has no `unpaid`/`paid in full` literal; Paid-in-Full / Partially Paid / Unpaid must be derived from `paid_amount` vs `total` + installment rollups (data is present; logic is unbuilt).
- **G. Order → Show link** — `Order` has **no direct `show_id`**; Associated Shows / Event Name / City / Event Dates / onsite contact are all derived via `OrderItem.show_product_id → ShowProduct → Shows`. Multi-show grouping + non-show order types (subscription/ppl_addon) are unhandled.
- **H. Invoice PDF** — `Invoice` has no stored PDF/`file_url`; a working pdfkit+S3 renderer exists but is **PPL-specific** and must be generalized to product/booth orders.
- **I. Pay-early endpoint** — charge primitives exist, but there is **no route to pay an existing order's scheduled installment early**; only `POST /payments/checkout` (creates a *new* order) exists.
- **J. Salesperson payment schedule** — installment rows are readable, but a salesperson-**defined** custom schedule (arbitrary dates/amounts) is not modeled in the cart; only system-derived `payment_mode=split` installments exist.
- **K. Onsite contact** — `OnsiteBoothContact` is keyed by `(company_id, show_id)`, **not order-linked**; must be resolved per show, multi-show yields multiple contacts.

## Missing referenced stories (please share)
`Payment Schedule Visibility`, `Credit Card Payment Workflow`, `Booth Upgrade`, `View Onsite Booth Contact` — referenced by 13.2/13.3 but not in this file.

See **`Order History - Open Questions for BA.xlsx`** for the consolidated clarification list (3 high-priority structural questions + per-requirement questions).
