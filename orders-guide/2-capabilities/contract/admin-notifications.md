# Admin Notifications — contract

> Exact behavior contract for the **[Admin Notifications](../admin-notifications.md)** capability. These are **not** admin REST routes — they are a mailer side-effect (24.11) and a worker cron (24.15). Authoritative source: the cancel/refund flows in [`admin-backend-api/src/admin/orders/services/`](../../../admin-backend-api/src/admin/orders/services) and the reminder job in [`background-worker-service`](../../../background-worker-service).

## Flow
![Admin Notifications sequence](admin-notifications.svg)

## Triggers

| Trigger | Kind | Fired by / When | Notes |
|---|---|---|---|
| Cancellation / refund email (24.11) | Mailer side-effect | [Cancel](../admin-cancellation.md) / [Refund](../admin-refunds.md) when `send_notification` is set | One email per action; self-seeds its own template slugs. |
| Payment reminders (24.15) | Scheduled cron | `background-worker-service` on a schedule | Scans upcoming/overdue installments; email-only; idempotent per reminder. |
| `POST background-worker-service /manual-trigger/payment-reminders/run` | Dev-only HTTP trigger | Manual QA run of the reminder job | Not a production/admin route. |

## Contract notes

- **No admin endpoint.** Nothing here lives in `orders.controller.ts`. `send_notification` on cancel/refund is the switch that fires 24.11.
- **One email per action** — no batching, no digest.
- **Template ownership** — each flow seeds and owns its slugs/templates; the Email & SMS epic manages templates but does not own these order emails.
- **Idempotency** — the reminder cron does not double-send for the same installment/window.

## Status / outcomes

| Signal | When |
|---|---|
| Email sent | `send_notification=true` on a successful cancel/refund; or a reminder-eligible installment on the cron pass. |
| No email | `send_notification` unset/false; or no reminder-eligible installments. |
| `200` (dev trigger) | Manual reminder run accepted (worker service, dev only). |

---
*Regenerate diagram: `npx -y @mermaid-js/mermaid-cli mmdc -i admin-notifications.mmd -o admin-notifications.svg -b white -p ../../pptr.json`*
