# Admin Notifications

## What it does

The **order-lifecycle emails** — two stories with no admin-facing REST route of their own: **24.11** (Order Cancellation email, formalized by SBE-1179) and **24.15** (Payment Reminder Notifications). The cancel/refund flows send **one email per admin action** through a dedicated **`OrderNotificationService`** (in `src/admin/orders/services/`), which owns three seeded templates:

- **`order_canceled`** — always sent for a notified cancellation (refund tokens degrade to "None"/"Not applicable" when no money moved).
- **`order_refunded`** — sent by the standalone refund flow (`POST :id/refunds`) when notified.
- **`gift_certificate_restored`** *(SBE-1179)* — a separate email to the **certificate purchaser/holder** whenever a cancel or refund returns value to their voucher.

24.15 is a **background-worker cron** that scans for upcoming/overdue installments and emails payment reminders — email-only, no admin endpoint; a dev-only manual trigger exists in the worker service for testing. This card exists because these are real, shipped behavior a newcomer will otherwise not find in the admin controller — they live in `OrderNotificationService` and the worker, not in `orders.controller.ts`.

## Its neighborhood

![Admin Notifications ego diagram](ego/admin-notifications.svg)

📋 **Need the exact contract?** → [Admin Notifications contract](contract/admin-notifications.md) (triggers, template ownership, the worker trigger)

## Endpoints

| Method | Path | Purpose | Notes |
|---|---|---|---|
| *(no REST route)* | `order_canceled` email | Sent by the [cancel](admin-cancellation.md) flow when `send_notification` is set. | `OrderNotificationService.sendOrderCanceledEmail`. |
| *(no REST route)* | `order_refunded` email | Sent by the standalone [refund](admin-refunds.md) flow when `send_notification` is set. | `OrderNotificationService.sendOrderRefundedEmail`. |
| *(no REST route)* | `gift_certificate_restored` email *(SBE-1179)* | Sent to the certificate holder when a cancel/refund restores voucher balance. | `OrderNotificationService.sendGiftCertificateRestoredEmail`. |
| `POST` | `background-worker-service /manual-trigger/payment-reminders/run` | **Dev-only** manual trigger to run the payment-reminder cron on demand. | Not a production/admin route; the real driver is the scheduled cron. |

## Flow, read as steps

1. **Cancel/refund emails (24.11 + SBE-1179):** when [Admin Cancellation](admin-cancellation.md) or [Admin Refunds](admin-refunds.md) runs with `send_notification` true, the flow calls `OrderNotificationService` **post-commit**. A cancellation sends `order_canceled`; a standalone refund sends `order_refunded`; either sends an extra `gift_certificate_restored` email to the holder when a certificate was topped up. One send per action — no digest, no retry loop. Both public methods **swallow every error** (a failed email never fails the cancel/refund). The templates are self-seeded (`trigger-event.seeder` + `notification-template.seeder`), not borrowed from the Email & SMS epic.
2. **Payment reminders (24.15):** a `background-worker-service` cron periodically queries orders with scheduled installments approaching or past their due date and sends reminder emails. It is email-only and idempotent per reminder; the dev-only `manual-trigger` route lets QA run it without waiting for the schedule.

## Why it matters / gotchas

- **These aren't in the admin controller.** Don't grep `orders.controller.ts` for them — the emails live in `OrderNotificationService`; 24.15 lives in `background-worker-service`.
- **`send_notification` is the switch.** Cancel and refund accept `send_notification`; the email fires only when it's set.
- **Three templates, not one.** `order_canceled` (cancel), `order_refunded` (standalone refund), `gift_certificate_restored` (holder, SBE-1179). A cancel that also restores a certificate sends two emails.
- **Emails are best-effort.** `OrderNotificationService` swallows send failures — a mailer hiccup never rolls back or fails the cancel/refund.
- **Privacy-scoped.** The cancel/refund SELECTs load no customer-identifying fields; the notification service resolves the recipient chain itself.
- **Template ownership.** These slugs are self-seeded here; the Email & SMS epic manages templates but does not own these order emails.
- **The worker route is dev-only.** `manual-trigger/payment-reminders/run` exists for testing; production reminders come from the cron schedule, not an admin click.

## Next

[Admin Cancellation](admin-cancellation.md) · [Admin Refunds](admin-refunds.md) · [Admin Quick Actions](admin-quick-actions.md)
