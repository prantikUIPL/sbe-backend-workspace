# Order APIs — Order Management & Order History

A guide to **what the order APIs do and how a request flows** across the two order epics we shipped — **Order Management** (admin-facing, Epic 24 / SBE-1078) and **Order History** (exhibitor-facing, Epic 13 / SBE-1146). Built to help a newcomer form a **working mental model of the behavior**, not to be an exhaustive API reference. Derived from the shipped controllers/services (`admin-backend-api/src/admin/orders/`, `exhibitor-backend-api/src/orders/`) — the routes here are the *real, live* decorators, not proposals.

> **Sibling guide:** [`../relationship/`](../relationship/README.md) documents the **nouns** (the Order/Company/Invoice… data model). This guide documents the **verbs** (the endpoints and flows that act on them). Capability cards here link across to the entity cards there.

## How this is organised (read in this order)

Layered so you never hold more than a few things in your head at once. Start at the top, go down only as far as you need.

| Level | What it is | Open this |
|---|---|---|
| **0 — Orient** | One-line definitions + a "what I want to do → which endpoint" map + the admin-vs-exhibitor split | **[glossary.md](glossary.md)** |
| **1 — Connect** | Two worked examples (an exhibitor views an order; an admin cancels + refunds one) that thread the endpoints together | **[the stories](1-the-story/)** |
| **2 — Zoom in** | One short card + one focused diagram per **capability** — *this is the core* | **[capability cards](2-capabilities/)** |
| **2½ — Contract** | Per-capability **request/response contract**: routes, params, response fields, status codes (linked 📋 from each card) | **[2-capabilities/contract/](2-capabilities/contract/)** |
| **3 — See it all** | The dense reference maps + the full endpoint catalog (for when you already know the pieces) | **[diagrams/](diagrams/)** |

> **New here? Do this:** skim the [glossary](glossary.md) (2 min) → read [an exhibitor views their order](1-the-story/an-exhibitor-views-their-order.md) (4 min) → open the [Exhibitor Order Details](2-capabilities/exhibitor-order-details.md) and [Admin Order Details](2-capabilities/admin-order-details.md) cards. That's enough to navigate the order modules.

## Why it's built this way (the research)

Same pedagogy as the [entity guide](../relationship/README.md), applied to behavior instead of schema. The two order controllers expose **25 live routes** across **15 stories** — dumping them as one flat list asks you to track everything at once. Instead:

- **Cognitive Load Theory** — working memory holds only ~4 interacting elements at once; a diagram past that overloads rather than teaches. So every Level-2 diagram centers **one capability and ≤7 direct neighbors** (its endpoints, handler service, the entities it touches, the DTO it returns), with the rest moved into prose (`*Also touches:*`).
- **Ego-network diagrams** — center one capability ("ego"), draw only its 1-hop neighbors, omit neighbor-to-neighbor edges. Each diagram is a single digestible neighborhood; the links *between* capabilities live in *their* cards.
- **Progressive disclosure (C4-style)** — start broad, zoom in on demand: glossary → story → per-capability → *contract on demand* → full catalog.

Plus a **worked example** (Level 1): two concrete request→response scenarios narrated end-to-end are far stickier than a route table. And when you *do* need exact params and fields, the **contract view** (Level 2½) pairs a request-flow `sequenceDiagram` with a response **data dictionary** (every field: type, nullability, plain-English meaning), behind a 📋 link so the card stays about the *mental model*, not the field list. Each contract links back to the authoritative controller/service.

## The 10 capability cards (+ 1 cross-cutting)

The two surfaces, split by what an admin vs an exhibitor can do. **Headline capabilities in bold.** One extra **cross-cutting** card documents the RBAC layer that gates every admin route.

**Exhibitor surface — Epic 13 (Order History), 3 read-only routes, JWT-guarded, company-scoped:**
- **[Exhibitor Order Listing](2-capabilities/exhibitor-order-listing.md)** *(13.1 / 13.2 — `GET /orders`)*
- **[Exhibitor Order Details](2-capabilities/exhibitor-order-details.md)** *(13.3 — `GET /orders/:orderId` + invoice download)*

**Admin surface — Epic 24 (Order Management), 22 routes, permission-gated, all-orders:**
- **[Admin Order List & Query](2-capabilities/admin-order-list-and-query.md)** *(24.1–24.4 — `GET /orders`, filters/search/sort as query params)*
- **[Admin Order Details](2-capabilities/admin-order-details.md)** *(24.6 — `GET`/`PATCH /orders/:id`, sales-rep reassign)*
- **[Admin Quick Actions](2-capabilities/admin-quick-actions.md)** *(24.5 — agreement/invoice download, invite, resends, impersonate)*
- **[Admin Notes & Audit](2-capabilities/admin-notes-and-audit.md)** *(24.14 — `GET`/`PATCH /orders/:id/notes`)*
- **[Admin Payments & Payment Plans](2-capabilities/admin-payments-and-plans.md)** *(24.7 / 24.8 — payments view, plan CRUD, installment void)*
- **[Admin Refunds](2-capabilities/admin-refunds.md)** *(24.9 — refund options + issue refund)*
- **[Admin Cancellation](2-capabilities/admin-cancellation.md)** *(24.10 — two-phase cancel + refund + inventory release)*
- **[Admin Notifications](2-capabilities/admin-notifications.md)** *(24.11 / 24.15 — cancellation email + payment-reminder cron)*

**Cross-cutting — the access layer under every admin card:**
- **[Admin Permissions & RBAC Wiring](2-capabilities/admin-permissions-and-rbac.md)** *(the 21 `orders.*` permission keys, their 8 seeded permission groups, and how a role gets them)*

## Five things that trip everyone up

1. **The two surfaces are different servers, different auth.** The admin controller (`admin-backend-api`) is **permission-gated** (`@Permissions('orders.view')`) and sees **all orders**. The exhibitor controller (`exhibitor-backend-api`) is **JWT-guarded** and **company-scoped** — the company id is derived server-side from the token, never passed by the client. They share one Postgres DB and the same `Order` table, but no code.
2. **`GET /orders` is one endpoint per surface, not many.** Admin filters/search/sort (24.1–24.4) are all **query params** on the single admin list route; the exhibitor list is a separate, smaller route on its own server. Same path string, two different controllers.
3. **`Order.notes` is NOT the admin notes.** `Order.notes` is the exhibitor checkout **idempotency-key store** and is never exposed. The admin "Internal Notes" (24.14) is a net-new **`internal_notes`** column plus `payment_memo` / `invoice_note` / `additional_terms`. Don't wire the notes UI to `Order.notes`.
4. **"Void" ≠ "delete" ≠ "cancel".** Per-installment **void** (24.6 D-z) kills one scheduled/failed installment while the order stays live; installment **delete** (24.8) removes a scheduled installment and frees Unallocated Balance; whole-order **cancel** (24.10) cancels the order + cascades + releases inventory + refunds. Three distinct routes.
5. **Some things were never built this sprint.** Stories **24.12** (Booth Release) and **24.13** (Move/Change Show) are analysis-only — no endpoints (24.12's inventory-release logic was folded into 24.10's cancel). Catalog proposals `payment-status`, order-level `void`, `hubspot-sync`, `quickbooks-sync`, and both `move-show` routes were dropped, re-shaped, parked, or left out of scope — see [diagrams/04-endpoint-catalog.md](diagrams/04-endpoint-catalog.md).

## Regenerating the diagrams

Editable Mermaid sources sit beside their renders (`2-capabilities/ego/*.mmd` for the card ego diagrams, `2-capabilities/contract/*.mmd` for the request-flow sequence diagrams, `diagrams/*.mmd` for the full maps). To re-render (needs Node + a Chrome/Chromium install; `pptr.json` points Puppeteer at system Chrome):

```bash
# with @mermaid-js/mermaid-cli available (npx pulls it if not installed):
npx -y @mermaid-js/mermaid-cli mmdc -i 2-capabilities/ego/exhibitor-order-details.mmd \
  -o 2-capabilities/ego/exhibitor-order-details.svg -b white -p pptr.json
# loop over 2-capabilities/ego/*.mmd, 2-capabilities/contract/*.mmd and diagrams/*.mmd to rebuild all.
```

---

*Level 2 is the heart of this guide. The dense [Level-3 maps](diagrams/) remain for reference, but if you're learning the order APIs, stay in the cards.*
