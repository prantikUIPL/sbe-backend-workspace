# Level 1 — The story: an exhibitor views their order

One concrete scenario, narrated end-to-end, to introduce each endpoint the moment it first matters. Each **bold capability** links to its card; each `path` is a real route. Don't memorise — just follow the thread. This is the **exhibitor** surface (Order History, Epic 13, `exhibitor-backend-api`).

## The cast

- **Acme Co.** — a company that has exhibited at a few shows.
- **Dana** — Acme's exhibitor user, logged into the exhibitor portal. Her session carries a JWT; the backend reads `req.user.id` from it and never trusts a company id from the client.

## 1. Dana opens "My Orders"

The portal calls **[Exhibitor Order Listing](../2-capabilities/exhibitor-order-listing.md)** → `GET /orders`. The `JwtAuthGuard` turns Dana's token into `req.user.id`; the service resolves *her company* server-side and queries **[Order](../../relationship/2-entities/order.md)** with `where { company_id, deleted_at: null }` — no type or status narrowing, so her subscription and any `pending` orders show up alongside her booth purchases.

Each row comes back display-ready: a derived `payment_status` (`partially_paid` for the NYC booth she's paying in installments), the grouped `shows[]` it touches, the `total`, and two action flags — `can_pay` (true, she still owes) and `can_download_invoice` (true, a payment has settled so an invoice exists). Because she has orders, `isEmpty` is false and the table renders.

> The company scope is invisible in the URL — there is no `company_id` param. A different exhibitor's token simply resolves to a different company. That's the whole security model for this surface.

## 2. Dana clicks a row → the order details

The row's View action navigates to **[Exhibitor Order Details](../2-capabilities/exhibitor-order-details.md)** → `GET /orders/:orderId`. The service does one scoped `order.findFirst({ where: { id, company_id, deleted_at: null } })`. If Dana (or a curious script) passed an order id belonging to someone else, this returns `null` → **404** — no way to tell "doesn't exist" from "not yours".

For her real order it assembles the aggregate:
- the line items, split by `cart_item_type` into `booths`, `add_ons`, `sponsorships`;
- a `financial_summary` — subtotal, her coupon *or* gift-certificate (never both), fees, savings, `total`, `total_paid`;
- `payments[]` — the settled installments only (this is history, not the schedule); the card brand/last4 are resolved even for a card she later removed;
- the `agreement` block (she accepted the event terms);
- `onsite_contacts[]` — one entry per show; for the NYC show Acme saved a booth staffer, so `contact` is populated; for a show with none, `contact` is `null` (it never falls back to billing).

## 3. Dana downloads her invoice

She clicks Download Invoice. The same capability's sibling route, `GET /orders/:orderId/invoice`, runs `OrderInvoiceDocumentService.generate` — it resolves the order's **latest** persisted **[Invoice](../../relationship/2-entities/invoice.md)** (Option B: invoices exist only after a successful payment, and only for product orders) and returns `{ url }`. The portal opens the PDF. Had this been her subscription order, the same click would 404 — no product invoice to serve.

## The whole story in one breath

> Dana's token → **[listing](../2-capabilities/exhibitor-order-listing.md)** (`GET /orders`, company-scoped, derived status + action flags) → View → **[details](../2-capabilities/exhibitor-order-details.md)** (`GET /orders/:orderId`, one scoped `findFirst` → 404 if not hers, booths/add-ons/sponsorships + financials + settled payments + agreement + per-show onsite contacts) → Download Invoice (`GET /orders/:orderId/invoice`, latest persisted invoice, product-only). Three read-only routes, company scope from the JWT throughout, no code shared with the admin side.

**Next:** the other side of the coin — [an admin cancels and refunds an order →](an-admin-cancels-and-refunds-an-order.md) · or open the [Exhibitor Order Details](../2-capabilities/exhibitor-order-details.md) card.
