# Admin Refunds — contract

> Exact request/response contract for the **[Admin Refunds](../admin-refunds.md)** capability. Authoritative source: [`admin-backend-api/src/admin/orders/orders.controller.ts`](../../../admin-backend-api/src/admin/orders/orders.controller.ts) (`getRefundOptions`, `createRefund`), service [`services/order-refund.service.ts`](../../../admin-backend-api/src/admin/orders/services/order-refund.service.ts), DTO `dto/order-refunds.dto.ts`; Stripe wrapper in `external-api-service`.

## Request flow
![Admin Refunds sequence](admin-refunds.svg)

## Requests

| Method | Path | Permission | Params / Body |
|---|---|---|---|
| `GET` | `/api/v1/orders/:id/refund-options` | `orders.refund.read` | `id`. → `OrderRefundOptionsResponseDto`. |
| `POST` | `/api/v1/orders/:id/refunds` | `orders.refund` | Body `CreateOrderRefundDto`: `payment_transaction_id?` (omit = order-level, newest-first), `amount`, `method` (`stripe`\|`manual`), `reason` (mandatory), `send_notification?` (default true). → `OrderRefundResponseDto`. |
| `POST` | `external-api-service /v1/refunds` *(internal)* | — | `stripe.refunds.create` wrapper — one charge + amount per call, DB-free. |

## Response shapes

**`OrderRefundOptionsResponseDto`** — per settled installment (newest first): available `methods` (Manual always; Stripe only with a charge), `already_refunded` (pending + succeeded ledger), `remaining_cap`; plus order aggregates: gross `paid_amount`, `net_paid` (gross − succeeded refunds), order-level `cap` (Σ per-installment caps).

**`OrderRefundResponseDto`** — per-leg outcomes: each targeted installment's refund status (`succeeded` / `refund_failed`), amount, method, and the ledger row id. An installment flips to `refunded` only when fully refunded; the order becomes `refunded` once every settled installment is.

## Status codes

| Code | When |
|---|---|
| `200` | Refund options retrieved. |
| `201` | Refund processed (per-leg outcomes returned; a Stripe leg may be recorded as a failed leg). |
| `400` | Missing amount/reason; amount exceeds the per-installment or order remaining cap (error quotes the exact `$` amount); Stripe unavailable (no charge — use Manual). |
| `403` | Missing `orders.refund.read` / `orders.refund`. |
| `404` | Unknown / soft-deleted / non-product order. |

---
*Regenerate diagram: `npx -y @mermaid-js/mermaid-cli mmdc -i admin-refunds.mmd -o admin-refunds.svg -b white -p ../../pptr.json`*
