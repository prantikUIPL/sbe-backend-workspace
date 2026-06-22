# Invoice

## What it is
The **billing document** for an [Order](order.md), with dual Stripe + QuickBooks sync. One order can produce **several** invoices (an initial one plus one per subscription renewal cycle), and an invoice can even arrive *before* its order exists.

## Its neighborhood
![Invoice ego diagram](ego/invoice.svg)

## Relationships, read as sentences
- An Invoice **bills** at most one **[Order](order.md)** (N→1, `SetNull`; `order_id` is nullable).
- An Invoice **is billed to** one **[Company](company.md)** (N→1, cascade).
- An Invoice **is itemized by** many **InvoiceLineItem** rows (1→N, cascade).
- An Invoice **is settled by** many **[PaymentTransactions](payment-transaction.md)** (1→N, `SetNull`).

## Why it matters / gotchas
- **`order_id` is nullable on purpose:** Stripe subscription invoices may land before the Order row is created, so they're linked up afterwards.
- One Order → many Invoices (initial + renewals) — don't assume a 1:1.
- `stripe_invoice_id` is unique (webhook dedup); `quickbooks_*` fields track the second sync target. Soft-delete only.

## Next
[Order](order.md) · [PaymentTransaction](payment-transaction.md) · [Company](company.md)
