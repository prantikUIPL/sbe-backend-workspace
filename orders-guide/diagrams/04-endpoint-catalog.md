# Level 3 — Full endpoint catalog

The complete, dense reference: **every route** across both order epics, plus the catalog proposals that were **dropped / re-shaped / parked / blocked / out-of-scope** so you know why they don't exist. For the mental model, stay in the [capability cards](../2-capabilities/); this is the "I already know the pieces" lookup.

Verified against the shipped controllers — [`admin-backend-api/src/admin/orders/orders.controller.ts`](../../admin-backend-api/src/admin/orders/orders.controller.ts) (22 live route handlers) and [`exhibitor-backend-api/src/orders/orders.controller.ts`](../../exhibitor-backend-api/src/orders/orders.controller.ts) (3 live routes).

## Exhibitor surface — Order History (Epic 13, JWT-guarded, company-scoped)

| # | Method | Path | Story | Permission/Auth | Capability |
|---|---|---|---|---|---|
| 1 | `GET` | `/orders` | 13.1 / 13.2 | JWT | [Exhibitor Order Listing](../2-capabilities/exhibitor-order-listing.md) |
| 2 | `GET` | `/orders/:orderId` | 13.3 | JWT | [Exhibitor Order Details](../2-capabilities/exhibitor-order-details.md) |
| 3 | `GET` | `/orders/:orderId/invoice` | 13.2-g / 13.3-s | JWT | [Exhibitor Order Details](../2-capabilities/exhibitor-order-details.md) |

## Admin surface — Order Management (Epic 24, permission-gated, all orders)

| # | Method | Path | Story | Permission | Capability |
|---|---|---|---|---|---|
| 1 | `GET` | `/api/v1/orders` | 24.1–24.4 | `orders.list` | [List & Query](../2-capabilities/admin-order-list-and-query.md) |
| 2 | `GET` | `/api/v1/orders/:id` | 24.6 | `orders.view` | [Order Details](../2-capabilities/admin-order-details.md) |
| 3 | `PATCH` | `/api/v1/orders/:id` | 24.6 | `orders.update` | [Order Details](../2-capabilities/admin-order-details.md) |
| 4 | `PATCH` | `/api/v1/orders/:id/sales-rep` | 24.6 | `orders.sales_rep.update` | [Order Details](../2-capabilities/admin-order-details.md) |
| 5 | `POST` | `/api/v1/orders/:id/payments/:transaction_id/void` | 24.6 (D-z) | `orders.payments.void` | [Payments & Plans](../2-capabilities/admin-payments-and-plans.md) |
| 6 | `GET` | `/api/v1/orders/:id/notes` | 24.14 | `orders.notes.read` | [Notes & Audit](../2-capabilities/admin-notes-and-audit.md) |
| 7 | `PATCH` | `/api/v1/orders/:id/notes` | 24.14 | `orders.notes.update` | [Notes & Audit](../2-capabilities/admin-notes-and-audit.md) |
| 8 | `GET` | `/api/v1/orders/:id/agreement.docx` | 24.5 | `orders.agreement.read` | [Quick Actions](../2-capabilities/admin-quick-actions.md) |
| 9 | `GET` | `/api/v1/orders/:id/agreement.pdf` | 24.5 | `orders.agreement.read` | [Quick Actions](../2-capabilities/admin-quick-actions.md) |
| 10 | `GET` | `/api/v1/orders/:id/invoices/:invoiceId/invoice` | 24.5 | `orders.invoice.read` | [Quick Actions](../2-capabilities/admin-quick-actions.md) |
| 11 | `POST` | `/api/v1/orders/:id/invite-user` | 24.5 | `orders.invite-user` | [Quick Actions](../2-capabilities/admin-quick-actions.md) |
| 12 | `POST` | `/api/v1/orders/:id/resend-confirmation` | 24.5 | `orders.resend-confirmation` | [Quick Actions](../2-capabilities/admin-quick-actions.md) |
| 13 | `POST` | `/api/v1/orders/:id/resend-portal-password` | 24.5 | `orders.resend-portal-password` | [Quick Actions](../2-capabilities/admin-quick-actions.md) |
| 14 | `POST` | `/api/v1/orders/:id/impersonate` | 24.5 | `orders.impersonate` | [Quick Actions](../2-capabilities/admin-quick-actions.md) |
| 15 | `GET` | `/api/v1/orders/:id/refund-options` | 24.9 | `orders.refund.read` | [Refunds](../2-capabilities/admin-refunds.md) |
| 16 | `POST` | `/api/v1/orders/:id/refunds` | 24.9 | `orders.refund` | [Refunds](../2-capabilities/admin-refunds.md) |
| 17 | `POST` | `/api/v1/orders/:id/cancel` | 24.10 | `orders.cancel` | [Cancellation](../2-capabilities/admin-cancellation.md) |
| 18 | `GET` | `/api/v1/orders/:id/payment-plan` | 24.8 | `orders.payment-plan.read` | [Payments & Plans](../2-capabilities/admin-payments-and-plans.md) |
| 19 | `GET` | `/api/v1/orders/:id/payments` | 24.7 | `orders.payments.read` | [Payments & Plans](../2-capabilities/admin-payments-and-plans.md) |
| 20 | `POST` | `/api/v1/orders/:id/payment-plan/installments` | 24.8 | `orders.payment-plan.create` | [Payments & Plans](../2-capabilities/admin-payments-and-plans.md) |
| 21 | `PATCH` | `/api/v1/orders/:id/payment-plan/installments/:installment_id` | 24.8 | `orders.payment-plan.update` | [Payments & Plans](../2-capabilities/admin-payments-and-plans.md) |
| 22 | `DELETE` | `/api/v1/orders/:id/payment-plan/installments/:installment_id` | 24.8 | `orders.payment-plan.delete` | [Payments & Plans](../2-capabilities/admin-payments-and-plans.md) |

> 22 rows above = **22 distinct route handlers** on the admin orders controller. (Three of them share two path strings: `POST` + `PATCH` + `DELETE` on `…/payment-plan/installments[/:installment_id]`.) `GET /api/v1/cities`, reused by 24.2's filter, lives outside the orders controller.

## Supporting / non-orders-controller routes

| Method | Path | Story | Where |
|---|---|---|---|
| `GET` | `/api/v1/cities` | 24.2-d | Existing city list, reused for the Show-City filter. |
| `GET` | `/api/v1/logs/admin-audit?entity_type=order&entity_id=:id` | 24.14 | Existing admin-audit route, reused for the note trail. |
| `POST` | `external-api-service /v1/refunds` | 24.9 | Internal Stripe `refunds.create` wrapper (DB-free). |
| `POST` | `background-worker-service /manual-trigger/payment-reminders/run` | 24.15 | Dev-only manual trigger for the reminder cron. |

## Proposed but NOT built (and why)

| Method | Path | Story | Status |
|---|---|---|---|
| `PATCH` | `/api/v1/orders/:id/payment-status` | 24.7 | **Dropped** (D3) — Mark-Paid/Unpaid moved to the 24.8 installment `PATCH`. |
| `POST` | `/api/v1/orders/:id/void` (order-level) | 24.6 | **Re-shaped** — became the per-installment `POST /payments/:transaction_id/void` (D-z). |
| `POST` | `/api/v1/orders/:id/send-email` | 24.6 | **Parked** (OQ-4) — template-selectable send, pending BA. |
| `POST` | `/api/v1/orders/:id/hubspot-sync` | 24.6 | **Parked** (OQ-5) — needs a `hubspot_deal_id` column. |
| `POST` | `/api/v1/orders/:id/quickbooks-sync` | 24.6 | **Blocked** — no QuickBooks integration (epic 65). |
| `POST` | `/api/v1/orders/:id/move-show[/validate]` | 24.13 | **Out of scope** this sprint (will reuse 24.10's `releaseForOrder`). |
| *(none)* | Booth Release endpoint | 24.12 | **Not built** — the inventory-release requirement is satisfied by `releaseForOrder` inside 24.10's cancel. |

---
*Regenerate the map diagrams: `npx -y @mermaid-js/mermaid-cli mmdc -i 00-order-surface-overview.mmd -o 00-order-surface-overview.svg -b white -p ../pptr.json` (repeat for `01`, `02`, `03`, `05`).*
