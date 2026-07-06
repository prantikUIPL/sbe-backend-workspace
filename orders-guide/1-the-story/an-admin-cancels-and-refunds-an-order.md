# Level 1 — The story: an admin cancels and refunds an order

The **admin** surface (Order Management, Epic 24, `admin-backend-api`), narrated end-to-end. Same shape as the [exhibitor story](an-exhibitor-views-their-order.md), but here the caller is a staff operator, auth is **permission-based**, and the operations **write**. Each **bold capability** links to its card.

## The cast

- **Morgan** — a support admin, logged into the admin panel. Every route checks a specific permission (`orders.view`, `orders.cancel`, …), not company ownership — Morgan can act on **any** order.
- **Order #4821** — Acme's NYC booth order, `partially_paid`: a deposit settled, two installments still scheduled.

## 1. Morgan finds the order

Morgan searches the admin table — **[Admin Order List & Query](../2-capabilities/admin-order-list-and-query.md)** → `GET /orders?search=acme&sort_by=created_at`. Filters, search, and sort are all query params on this one endpoint (that's stories 24.1–24.4 combined). No company scoping — the `orders.list` permission is the only gate. Morgan clicks the row.

## 2. Morgan opens the full order view

**[Admin Order Details](../2-capabilities/admin-order-details.md)** → `GET /orders/:id` runs one `order.findFirst({ where: { id, deleted_at: null } })` — no scope, no type filter — and derives the whole operational picture: the six-value `status_display`, the billing block, the display-only notes (from **[Admin Notes & Audit](../2-capabilities/admin-notes-and-audit.md)** — never `Order.notes`), the customer link, the line-item tree, and the totals block whose `balance_due` is already **net of the refund ledger**. The `payment_plan` block shows the deposit as `succeeded` and two `scheduled` installments (each rendered by the shared 24.8 C13 mapper). This screen *reads* from half a dozen capabilities but *owns* none of their writes.

## 3. Morgan decides to cancel — and previews first

Acme asks to cancel. Morgan hits **[Admin Cancellation](../2-capabilities/admin-cancellation.md)** → `POST /orders/:id/cancel` **without** `confirm`. That's a dry run: it returns exactly what *would* happen — the two scheduled installments that would be canceled, the booth **inventory reservation** that would be released, and the refund legs (the settled deposit, newest-first) with a total — and **writes nothing**. Morgan sees the numbers and proceeds.

> If a Stripe charge were mid-flight on this order, even the preview would return **409 `CHARGE_IN_FLIGHT`**. Morgan would wait a minute and retry. Not the case here.

## 4. Morgan confirms — the cascade runs

Morgan re-sends with `?confirm=true` and `refund_type: full`, a reason, and `send_notification: true`. In one transaction the service takes `FOR UPDATE` locks on the **[PaymentTransaction](../../relationship/2-entities/payment-transaction.md)** rows, flips #4821 to **Cancelled**, cascades the two scheduled installments to `canceled` (`next_retry_at` nulled, so no cron resurrects them), releases the booth reservation via `releaseForOrder` (this is where the never-built story 24.12's inventory logic actually lives), and writes the audit record. It commits.

## 5. The refund — and the email

Post-commit, the cancel hands off to the **[Admin Refunds](../2-capabilities/admin-refunds.md)** engine. `refund_type: full` means "refund the entire remaining refundable amount" — the settled deposit. Because that installment carries a Stripe charge, the engine calls the internal `external-api-service /v1/refunds` wrapper, writes a `Refund` ledger row, flips the installment to `refunded`, and — since every settled installment is now refunded — the order's status derives to `refunded` too. Every leg is audited with Morgan's reason.

Because `send_notification` was set, the cancel/refund flow fires the **[Admin Notifications](../2-capabilities/admin-notifications.md)** 24.11 email — one message to Acme, no batching. (Separately, the 24.15 worker cron keeps mailing payment reminders for *other* orders with upcoming installments; it has no admin route.)

> If the refund step had failed (a Stripe hiccup), #4821 would **stay canceled** and the response would state the exact refund state — cancellation is never rolled back by a refund failure. That separation is deliberate.

## The whole story in one breath

> `orders.*` permission (not ownership) → **[list/search](../2-capabilities/admin-order-list-and-query.md)** (`GET /orders`, filters as query params) → **[details](../2-capabilities/admin-order-details.md)** (`GET /orders/:id`, refund-net totals + C13 installments, reads many-owns-none) → **[cancel preview](../2-capabilities/admin-cancellation.md)** (`POST /:id/cancel`, writes nothing; 409 if a charge is in flight) → confirm (`?confirm=true` → lock, Cancelled, cascade installments, `releaseForOrder`, audit, commit) → **[refund](../2-capabilities/admin-refunds.md)** (post-commit, Stripe leg via the external wrapper, ledger row, order → `refunded`) → **[email](../2-capabilities/admin-notifications.md)** (24.11, one per action).

**Next:** open the [Admin Cancellation](../2-capabilities/admin-cancellation.md) card, or compare with [an exhibitor viewing their order](an-exhibitor-views-their-order.md).
