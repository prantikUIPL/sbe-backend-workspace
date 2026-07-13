# Level 0 — Glossary & endpoint map

Read this first. It gives you the vocabulary, a "what do I want to do → which endpoint" map, and the one split that explains everything: **admin vs exhibitor**.

## (a) The two surfaces, at a glance

|  | **Exhibitor** (Order History, Epic 13) | **Admin** (Order Management, Epic 24) |
|---|---|---|
| Server | `exhibitor-backend-api` | `admin-backend-api` |
| Base path | `/orders` | `/api/v1/orders` |
| Auth | `JwtAuthGuard` — the exhibitor is `req.user.id` | `@Permissions('orders.*')` per route |
| Scope | **Company-scoped** — company derived from the JWT, never passed in | **All orders** — no company scoping |
| Routes | **3**, all read-only `GET` | **22**, read + write |
| Order types served | product, subscription, ppl_addon (list); details across the same | product / subscription / ppl_addon / gift_certificate |
| Purpose | "Let me see my past & current orders" | "Let me operate on any order" |

The two never share code. They share one Postgres DB and the same `Order` table. Where they compute the same thing (e.g. the per-show onsite-contact block, the order-shows grouping), the logic is **reimplemented natively on each side**, not imported — see the no-duplication rule in `../relationship/`.

## (b) One sentence per capability

| Capability (card) | In one sentence |
|---|---|
| **[Exhibitor Order Listing](2-capabilities/exhibitor-order-listing.md)** | The exhibitor's paginated, company-scoped order table with derived payment status, grouped shows, and per-row action flags. |
| **[Exhibitor Order Details](2-capabilities/exhibitor-order-details.md)** | The read-only breakdown of one of the exhibitor's own orders (booths, add-ons, sponsorships, financials, payments, agreement, onsite contacts) + invoice PDF download. |
| **[Admin Order List & Query](2-capabilities/admin-order-list-and-query.md)** | The admin order table with filters, search, and sort — all as query params on one `GET /orders`. |
| **[Admin Order Details](2-capabilities/admin-order-details.md)** | The full admin aggregate for any order + billing/additional-emails edit + sales-rep reassignment. |
| **[Admin Quick Actions](2-capabilities/admin-quick-actions.md)** | Per-order operational shortcuts: download the signed agreement / an invoice, invite a portal user, resend confirmation / portal password, impersonate the customer. |
| **[Admin Notes & Audit](2-capabilities/admin-notes-and-audit.md)** | Read/write the admin-only notes bundle (internal notes, payment memo, invoice note, additional terms), every change audited. |
| **[Admin Payments & Payment Plans](2-capabilities/admin-payments-and-plans.md)** | The installment ledger and the payment-plan machinery — view payments, add/reschedule/mark-paid/delete installments, void one installment. |
| **[Admin Refunds](2-capabilities/admin-refunds.md)** | Per-installment refund eligibility + issuing Manual or Stripe refunds against an order. |
| **[Admin Cancellation](2-capabilities/admin-cancellation.md)** | Two-phase (preview → confirm) whole-order cancel that cascades installments, releases inventory, and refunds through the refund engine. |
| **[Admin Notifications](2-capabilities/admin-notifications.md)** | The cancellation email (one per action) and the payment-reminder worker cron. |
| **[Admin Permissions & RBAC Wiring](2-capabilities/admin-permissions-and-rbac.md)** *(cross-cutting)* | The 21 `orders.*` permission keys that gate every admin route, their 8 seeded permission groups (module `orders`), and how a role is granted them. |

## (c) "I want to… → which endpoint"

| You want to… | Surface | Endpoint |
|---|---|---|
| See my orders (exhibitor) | Exhibitor | `GET /orders` |
| Open one of my orders | Exhibitor | `GET /orders/:orderId` |
| Download my invoice | Exhibitor | `GET /orders/:orderId/invoice` |
| Browse / filter / search / sort all orders | Admin | `GET /orders` (query params) |
| Open an order's full admin view | Admin | `GET /orders/:id` |
| Edit billing / CC emails | Admin | `PATCH /orders/:id` |
| Reassign the sales rep | Admin | `PATCH /orders/:id/sales-rep` |
| Download the signed agreement | Admin | `GET /orders/:id/agreement.pdf` \| `.docx` |
| Download an invoice (admin) | Admin | `GET /orders/:id/invoices/:invoiceId/invoice` |
| Invite a portal user | Admin | `POST /orders/:id/invite-user` |
| Resend confirmation / portal password | Admin | `POST /orders/:id/resend-confirmation` \| `/resend-portal-password` |
| Log in as the customer | Admin | `POST /orders/:id/impersonate` |
| Read / edit internal notes | Admin | `GET` \| `PATCH /orders/:id/notes` |
| See the payments ledger | Admin | `GET /orders/:id/payments` |
| See / edit the payment plan | Admin | `GET /orders/:id/payment-plan` + `POST`/`PATCH`/`DELETE .../installments/:installment_id` |
| Void one scheduled/failed installment | Admin | `POST /orders/:id/payments/:transaction_id/void` |
| See refund options / issue a refund | Admin | `GET /orders/:id/refund-options` \| `POST /orders/:id/refunds` |
| Cancel an order | Admin | `POST /orders/:id/cancel?confirm=true` |
| See every order permission (flat) | Admin | `GET /permissions` (module `orders`) |
| Grant order permissions to a role (grouped) | Admin | `GET` \| `POST /roles/:id/permission-groups` |

## (d) Terms you'll hit in the cards

- **Order-details aggregate** — the single response the details endpoint assembles (header + line items + financials + payments + agreement + …), built by one scoped `findFirst` (→ 404 on miss) over a frozen `select`, plus a keyed follow-up lookup or two. Admin and exhibitor each have their own `order-details.service.ts`.
- **`payment_status` (derived)** — `paid_in_full` / `partially_paid` / `unpaid`, computed from `paid_amount` vs `total`. Distinct from the raw lifecycle `status` (pending/partially_paid/completed/canceled/failed/refunded).
- **`status_display` (admin, D1)** — a derived six-value label for the admin view; no enum migration was added.
- **Installment** — a `PaymentTransaction` row on the order. `credit_card` = Stripe-driven (the webhook is source of truth); `bank_wire_ach` / `check` / `paypal` = manual (an admin marks them paid).
- **Unallocated Balance (24.8, derived)** — `total − Σ installment amounts`, floored at 0. Deleting an installment *is* the return of its amount to this balance.
- **Refund ledger (24.9)** — `Refund` rows; the order's **net paid** = gross `paid_amount` − succeeded refunds; **balance due** on the admin details is net of this ledger.
- **Per-installment void (24.6 D-z)** — transitions one scheduled/failed installment to `canceled` with `next_retry_at` nulled — the exact terminal shape the cancel cascade writes, so no cron resurrects it.
- **Two-phase confirm (`?confirm=`)** — the cart idiom reused by cancel and by installment add/reschedule: without `confirm=true` the call is a **write-nothing preview**; with it, the call executes.
- **Option-B invoice (exhibitor)** — the exhibitor invoice endpoint serves the order's **latest persisted `Invoice`** (invoices exist only after a successful payment; product-only), rather than composing one on the fly.
- **Onsite booth contact** — the company's booth staffer for a given show, keyed `(company_id, show_id)`; surfaced per-show on both details aggregates, `null` when unset (no billing fallback). See `../relationship/2-entities/onsite-booth-contact.md`.
- **Shared units (U1–U20)** — the admin epic's ledger of build units owned by one story and consumed by others (e.g. the C13 installment-row mapper, the refund primitive). See [diagrams/03-shared-units.svg](diagrams/03-shared-units.svg).
- **Permission key (`orders.*`)** — one of 21 strings (e.g. `orders.view`, `orders.refund`, `orders.cancel`) seeded in `permission.seeder.ts`; each admin route carries a `@Permissions('orders.…')` decorator checked against these. See [Admin Permissions & RBAC Wiring](2-capabilities/admin-permissions-and-rbac.md).
- **Permission group** — a named bundle of permission keys within a module, seeded in `permission-group.seeder.ts` and surfaced on the grouped **Role Permissions** screen. The `orders` module has **8** groups (`View Orders` root + 7 action groups). Selecting a group in the assign flow expands it to its keys.
- **`depends_on` (permission group)** — a group's prerequisite group in the same module; resolved at assign time so enabling e.g. *Cancel Order* auto-pulls *View Orders*. Every `orders` action group depends on `View Orders`.
- **Convention A (group module = permission module)** — the `orders` groups set the group `module` string equal to the permission `module` (`orders`), following the **booth-agreements** precedent rather than the prettified-label style (`Cart Management`, `PPL Order`).

## (e) Not built this sprint (so you don't go looking)

- **24.12 Booth Release & Inventory Behaviour** and **24.13 Move/Change Show** — analysis/feasibility only, **no endpoints**. 24.12's inventory-release logic lives inside 24.10's cancel (`releaseForOrder`); 24.13 will reuse it next sprint.
- Catalog proposals that were **dropped / re-shaped / parked / blocked**: `PATCH /orders/:id/payment-status` (dropped → Mark-Paid moved to the 24.8 installment PATCH), order-level `POST /orders/:id/void` (re-shaped → per-installment void), `POST /orders/:id/send-email` (parked, pending BA), `POST /orders/:id/hubspot-sync` (parked), `POST /orders/:id/quickbooks-sync` (blocked — no QuickBooks integration), `POST /orders/:id/move-show[/validate]` (OOS). Full status in [diagrams/04-endpoint-catalog.md](diagrams/04-endpoint-catalog.md).

---

**Next:** [the stories →](1-the-story/) · or jump to a [capability card](2-capabilities/).
