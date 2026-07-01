# Order Epics — Build Consolidation & Redundancy Map

Generalizes the 13.1→13.2 insight across all stories: **build the owner once; the rest comes (largely) for free.** For each cluster: the story to build first, the single shared build unit, and the *residual delta* each dependent still needs.

> **Two views in this doc.** The clusters below answer *"what shared build unit does a story
> reuse."* The final section — **[Inter-Story & Cross-Epic Dependencies](#inter-story--cross-epic-dependencies-blockers-sequencing-external-providers)** —
> answers the inverse: *"what must ship elsewhere before a requirement can be delivered"*
> (cross-epic blockers with Jira/sprint status, plus requirements that turned out already-delivered
> or not-deliverable). It also **reconciles** cluster assumptions that later analysis changed.
> Source of truth remains each story's feasibility `.md`.


## Order Management

**Build-first owners (7):** 24.1, 24.10, 24.9, 24.14, 24.5, 24.12, 24.8 — building these covers the shared work in 13 clusters.

### C1 — One Order Management list endpoint serves the list container + filters + search + sorting
*shared-implementation · recommend **build-once-reuse** · confidence high*

- **Build first:** `24.1`
- **Shared build unit (build once):** GET /api/v1/orders — the single paginated/filterable/searchable/sortable list query (Prisma findMany over Order where order_type=product with RBAC) plus its row projection (order_number, customer/company, item total, balance due, show, sales person, sales channel, date)
- **Effort saved:** Avoids designing/reviewing 4 separate list endpoints. Filters, search and sorting are query-param layers on ONE controller+service+DTO+test surface, not independent builds. Pagination, RBAC, row projection and empty-state are written once and inherited by all four.
- **Evidence:** endpointCatalog GET /api/v1/orders stories[24.1,24.2,24.3,24.4]; verified near-identical pattern at admin/ppl-order/ppl-order.service.ts (sortBy/sortOrder :90-100, created_at date-range :293, insensitive contains over order_number+company.name :299-300, filter order_type IN [subscription,ppl_addon] :280 — confirming the product-order list is net-new and customer-name search is additional)
- **Members:**
    - `24.1` [24.1-a, 24.1-c, 24.1-d, 24.1-f, 24.1-g, 24.1-h, 24.1-i, 24.1-j, 24.1-k, 24.1-l, 24.1-m, 24.1-n] _(owner)_ — shares-endpoint; **residual:** owner — the base list query, row projection, pagination, RBAC and totals/balance columns. Booth-build rows (24.1-b) are Blocked (no producer) and stay out; Quick Links (24.1-e) is Out of Scope (belongs to 24.5).
    - `24.2` [24.2-a, 24.2-b, 24.2-c, 24.2-e, 24.2-f, 24.2-g, 24.2-h, 24.2-i] — shares-endpoint; **residual:** the from_date/to_date + show_city_id + sales_channel query params and their WHERE logic (incl. End>=Start validation, the OrderItem->ShowProduct->Show->City join for show-city [Partial: only cart-originated product orders carry show_product_id], and the cart.created_by_type derivation for sales-channel [Partial: null for non-cart orders]). 24.2-d (city dropdown) is NOT here — it reuses GET /api/v1/cities. 24.2-i is a frontend calendar-picker concern, not endpoint work. Empty-state (24.2-g) and backend-enforcement (24.2-h) are inherent to the shared endpoint = no extra work.
    - `24.3` [24.3-a, 24.3-b, 24.3-c, 24.3-d, 24.3-e, 24.3-f, 24.3-g] — shares-endpoint; **residual:** the single search query param with the insensitive-contains OR over order_number + company.name + billing_first/last_name. VERIFIED net-new: the ppl-order search (ppl-order.service.ts:299-300) covers only order_number + company.name, so the customer-name (billing first/last) clause is genuinely additional. Empty-state/backend (24.3-f/g) come free with the endpoint.
    - `24.4` [24.4-a, 24.4-b, 24.4-c] — shares-endpoint; **residual:** the sortBy/sortOrder params mapped to Prisma orderBy for order_number and created_at only — small (ppl-order.service.ts:90-100 is the exact precedent). Full-dataset enforcement (24.4-c) is inherent to server-side sort.

### C2 — One Order cancel endpoint serves cancellation + inventory release + cancellation email
*shared-implementation · recommend **build-once-reuse** · confidence high*

- **Build first:** `24.10`
- **Shared build unit (build once):** POST /api/v1/orders/:id/cancel — one $transaction: refund cap vs Order.paid_amount, Order.status=canceled, flip unpaid/pending PaymentTransactions to canceled, release committed InventoryReservation rows, optional cancellation email, AdminAuditLog(entity_type=order)
- **Effort saved:** Three stories each proposed POST .../cancel. Building one endpoint avoids three competing cancel routes and three reviews; inventory release and the email toggle become in-transaction steps of the single cancel service, not separate features.
- **Evidence:** endpointCatalog POST /api/v1/orders/:id/cancel stories[24.10,24.11,24.12]; inventory release pattern proven at external-api-service/src/modules/webhook/services/webhook.service.ts:2762-2765 (updateMany {order_id, status:committed} -> {status:released, released_at}); AdminAuditService.record at admin/common/audit/admin-audit.service.ts reused across configuration/gift-certificates/shows-management/account-history-notes
- **Members:**
    - `24.10` [24.10-a, 24.10-b, 24.10-c, 24.10-e, 24.10-f, 24.10-i] _(owner)_ — shares-endpoint; **residual:** owner — status flip + installment cancel + refund cap + Stripe-refund leg + audit log. Partial-refund accounting / Refund-record (24.10-d/h) and offline-refund marking (24.10-g) remain Blocked on the Refund-Management primitive. 24.10-j (per-plan refunds instead of full cancel) is Out of Scope.
    - `24.12` [24.12-a, 24.12-b, 24.12-c, 24.12-e, 24.12-f] — shares-endpoint; **residual:** the inventory-release call (flip committed->released by order_id for booth + non-booth lines) plus the manual-floorplan-release reminder flag returned in the cancel response. NOTE: the release helper itself is the shared build unit of C12 (net-new in admin-backend-api — no admin-side release method exists today). Auto Social-Tables release (24.12-d) stays Blocked. 24.12-a is the same cancel action as 24.10 = no separate endpoint.
    - `24.11` [24.11-a, 24.11-b, 24.11-c, 24.11-d, 24.11-e] — shares-logic; **residual:** the send_notification boolean param (default true) on the cancel request + the conditional MailerService.sendFromTemplate dispatch; still needs the cancellation trigger_event slug + template seeded. Same toggle is reused by the refund endpoint (see C3/C4).

### C3 — One Order refund endpoint serves refund management + 24.6 refund action + refund-email notice
*shared-implementation · recommend **build-once-reuse** · confidence high*

- **Build first:** `24.9`
- **Shared build unit (build once):** POST /api/v1/orders/:id/refunds — validate cap (paid_amount minus prior refunds) + mandatory reason, persist Refund record, set Refunded / Refund Failed, optional refund email; calls external-api-service /v1/refunds for the Stripe leg
- **Effort saved:** 24.6's refund action and 24.11's refund-email do not get their own routes/services; they are delivered by 24.9's single refund endpoint. Avoids duplicate refund implementations and reviews.
- **Evidence:** endpointCatalog POST /api/v1/orders/:id/refunds stories[24.9,24.6,24.11]; external-api-service /v1/refunds (stripe.refunds.create wrapper, internal) — VERIFIED ABSENT today (grep for refunds.create returns nothing across all repos), so it is net-new
- **Members:**
    - `24.9` [24.9-a, 24.9-b, 24.9-c, 24.9-d, 24.9-e, 24.9-g, 24.9-h] _(owner)_ — shares-endpoint; **residual:** owner — the Refund model, refund_failed enum value, cap/reason validation, status transitions, and the Stripe wrapper call. 24.9-f (manual-only for offline-paid) stays Partial pending an offline-payment-recording story; 24.9-i (QuickBooks tracking) is Out of Scope.
    - `24.6` [24.6-z] — shares-endpoint; **residual:** the refund HALF of 24.6-z is delivered by this endpoint. The VOID half is a SEPARATE endpoint (POST .../void) and remains Blocked (no Stripe void path / no Refund model) — do not fold void here. 24.6-z is overall Blocked in the input precisely because of the void half + net-new Refund model.
    - `24.11` [24.11-a, 24.11-b, 24.11-c, 24.11-d, 24.11-e] — shares-logic; **residual:** the send_notification toggle on the refund request + conditional refund-email dispatch — the SAME toggle logic as on the cancel endpoint (C2); needs the refund trigger_event/template seeded.

### C4 — 24.11 (cancel/refund email toggle) is entirely delivered by the cancel + refund endpoints
*subsumed-story · recommend **cross-reference** · confidence high*

- **Build first:** `24.10`
- **Shared build unit (build once):** A single send_notification boolean (default true) + conditional MailerService.sendFromTemplate dispatch, applied identically on both POST .../cancel (24.10) and POST .../refunds (24.9)
- **Effort saved:** 24.11 needs no endpoint, controller, service or DTO of its own — its toggle is one request field reused on two endpoints. Review collapses to: confirm the boolean is honored server-side + the two templates/triggers are seeded.
- **Evidence:** endpointCatalog: 24.11 appears only as a member of POST .../cancel and POST .../refunds, introduces no route; MailerService.sendFromTemplate verified at background-worker-service/src/notification/mailer.service.ts:88 (writes notification_logs; reused by lead/low-balance/daily-summary crons)
- **Members:**
    - `24.11` [24.11-a, 24.11-b, 24.11-c, 24.11-d, 24.11-e] — subset; **residual:** the ONLY net-new work unique to 24.11 is seeding the cancellation and refund trigger_event slugs + notification templates (the notification-template create endpoint rejects a type with no matching trigger_event — gating detail from the 24.11 summary). The flag, default-checked behavior, unchecked-suppression and backend enforcement are inherent to the C2/C3 endpoints. Recommendation is cross-reference (NOT fold) because this template/trigger seeding is real, separately-deliverable work.

### C5 — 24.6's notes display/edit reqs are delivered by 24.14's notes sub-resource
*subsumed-story · recommend **cross-reference** · confidence high*

- **Build first:** `24.14`
- **Shared build unit (build once):** GET + PATCH /api/v1/orders/:id/notes — the single read/write path for internal notes, payment memo, invoice-note/PO, and additional terms (with per-change AdminAuditLog)
- **Effort saved:** Avoids two write paths for the same note fields. 24.6 references 24.14 instead of building note-editing; only the read display lives in 24.6's detail aggregate. 24.6-d becomes deliverable once 24.14's payment_memo column lands.
- **Evidence:** endpointCatalog PATCH /api/v1/orders/:id/notes stories[24.14,24.6]; Order.notes schema.prisma:1570; Cart.invoice_note/additional_terms schema.prisma:2811-2812 (not on Order); account-history-notes module (admin/account-history-notes/account-history-notes.service.ts) is the working transactional note-update + AdminAuditService.record template
- **Members:**
    - `24.14` [24.14-a, 24.14-b, 24.14-c, 24.14-d, 24.14-e, 24.14-f, 24.14-g] _(owner)_ — shares-endpoint; **residual:** owner — the notes GET/PATCH, the net-new payment_memo / invoice_note / additional_terms scalar columns on Order (VERIFIED: Order has only a free-text notes column at schema.prisma:1570; invoice_note/additional_terms exist on Cart at :2811-2812 but NOT on Order), and the audit-trail write.
    - `24.6` [24.6-c, 24.6-d, 24.6-e, 24.6-f] — subset; **residual:** the WRITE/EDIT of internal-notes / invoice-note / additional-terms / payment-memo is delivered by 24.14's PATCH .../notes (24.14-a/b/c/d) — these were removed from 24.6's PATCH .../:id. 24.6 retains only DISPLAY of these fields inside its GET .../:id aggregate (reading the columns 24.14 adds; no separate write path). NOTE: 24.6-d (Payment Memo) is 'Not Deliverable' in the input ONLY because the column does not exist yet — once 24.14 adds payment_memo + its PATCH (24.14-b), 24.6-d's edit IS delivered by 24.14 and only its display remains 24.6's. The catalog deliberately excludes 24.6-d from the notes-write requirements list, but the column dependency is real.

### C6 — Agreement PDF/DOCX download shared by Quick Actions (24.5) and Order Details (24.6)
*shared-implementation · recommend **cross-reference** · confidence high*

- **Build first:** `24.5`
- **Shared build unit (build once):** GET /api/v1/orders/:id/agreement.pdf and /agreement.docx (reuse AgreementDocumentService / buildSimplePdf over OrderAgreement)
- **Effort saved:** 24.6's agreement view/download is delivered by 24.5's two routes; no duplicate agreement endpoint or generator wiring.
- **Evidence:** endpointCatalog GET /api/v1/orders/:id/agreement.pdf and .docx stories[24.5,24.6]; AgreementDocumentService verified at admin/cart/services/agreement-document.service.ts (+ utils/pdf.util.ts)
- **Members:**
    - `24.5` [24.5-e, 24.5-f] _(owner)_ — shares-endpoint; **residual:** owner — the two format routes (.docx and .pdf) reusing the existing cart agreement generator (admin/cart/services/agreement-document.service.ts + utils/pdf.util.ts).
    - `24.6` [24.6-s] — subset; **residual:** none for the route — 24.6-s (view/download agreement) is format-agnostic and maps onto both routes 24.5 already builds; 24.6 introduces no separate agreement route. 24.6-s's 'Partial' verdict is a shared DATA caveat (not every order has an OrderAgreement row) that 24.5's routes inherit identically — it is not separate build work for 24.6.

### C7 — Stripe refund execution wrapper reused by refund + cancellation
*duplicate-requirement · recommend **build-once-reuse** · confidence high*

- **Build first:** `24.9`
- **Shared build unit (build once):** external-api-service POST /v1/refunds (internal) — stripe.refunds.create against the order/installment stripe_charge_id, returning status so callers set Refunded / Refund Failed
- **Effort saved:** One Stripe refund integration point instead of three. Cancel, refund-management and the Order-Details refund all hit the same external-api wrapper.
- **Evidence:** endpointCatalog external-api-service /v1/refunds (internal) stories[24.9]; VERIFIED grep 'refunds.create' returns nothing across admin/external/exhibitor repos (only inbound charge.refunded webhook handling exists)
- **Members:**
    - `24.9` [24.9-b, 24.9-g] _(owner)_ — duplicate; **residual:** owner — builds the outbound Stripe refund wrapper (VERIFIED none exists today).
    - `24.10` [24.10-f] — shares-logic; **residual:** the cancel endpoint's Stripe-refund leg CALLS this same wrapper; residual is only wiring the call into the cancel transaction. Partial-refund amount accounting stays Blocked (24.10-h).
    - `24.6` [24.6-z] — shares-logic; **residual:** the refund action invoked from Order Details routes through 24.9's endpoint which calls this wrapper; no separate Stripe call. (Void half of 24.6-z is unrelated and Blocked.)

### C8 — Backend RBAC / @Permissions enforcement repeated across every Order Management story
*duplicate-requirement · recommend **build-once-reuse** · confidence high*

- **Build first:** `24.1`
- **Shared build unit (build once):** The existing JWT + roles guard + @Permissions(...) decorator pattern applied on the Order Management controllers (no new mechanism — reuse src/auth/decorators/permissions.decorator.ts)
- **Effort saved:** "Enforced on the backend (RBAC/permissions)" is the same guard pattern in 13 stories. Recognize it as one reusable cross-cutting concern rather than re-analyzing/re-implementing auth per story; review focuses only on each route's permission KEY and any domain-specific gate.
- **Evidence:** src/auth/decorators/permissions.decorator.ts VERIFIED present; reused across admin modules
- **Members:**
    - `24.1` [24.1-m] _(owner)_ — duplicate; **residual:** define the order-list permission key + apply the guard.
    - `24.2` [24.2-h] — duplicate; **residual:** none beyond the list guard it already inherits (same endpoint as 24.1).
    - `24.3` [24.3-g] — duplicate; **residual:** none beyond the list guard (same endpoint).
    - `24.4` [24.4-c] — duplicate; **residual:** none beyond the list guard (same endpoint).
    - `24.5` [24.5-l] — duplicate; **residual:** per-action permission keys (e.g. Booth-Build role) + the actions GET that returns gated set.
    - `24.6` [24.6-y] — duplicate; **residual:** per-action keys for edit/refund/void/sync/reassign on the detail routes.
    - `24.7` [24.7-d] — duplicate; **residual:** the method-eligibility gate (manual-method-only) is extra DOMAIN logic on top of the shared guard (24.7-d is Partial for that reason).
    - `24.8` [24.8-m] — duplicate; **residual:** plan totals/allocation/date-rule enforcement is domain logic beyond the guard.
    - `24.9` [24.9-h] — duplicate; **residual:** refund cap + mandatory-reason validation beyond the guard.
    - `24.10` [24.10-i] — duplicate; **residual:** none beyond applying the guard on cancel (audit-log half of 24.10-i is C9).
    - `24.12` [24.12-f] — duplicate; **residual:** none — inventory release runs inside the guarded cancel endpoint.
    - `24.13` [24.13-h] — duplicate; **residual:** none beyond applying the guard on move-show.
    - `24.14` [24.14-g] — duplicate; **residual:** none beyond applying the guard on notes routes.

### C9 — AdminAuditLog (entity_type=order) write repeated across mutating stories
*duplicate-requirement · recommend **build-once-reuse** · confidence high*

- **Build first:** `24.14`
- **Shared build unit (build once):** AdminAuditService.record()/recordMany() with entity_type='order' (append-only, transaction-aware) — already implemented and in production use
- **Effort saved:** "Status changes / actions shall be logged" is the same audit primitive across 3 mutating stories. Build zero new logging infra; each story adds a single record() call. The audit READ is the already-built admin-audit-log GET route.
- **Evidence:** AdminAuditService verified at admin/common/audit/admin-audit.service.ts (record/recordMany), used by configuration/gift-certificates/shows-management/account-history-notes/product-categories/notification-template/pricing-tier; endpointCatalog GET /api/v1/logs/admin-audit already exposes entity_type=order + entity_id (ALREADY BUILT)
- **Members:**
    - `24.14` [24.14-e] _(owner)_ — duplicate; **residual:** owner of the order-notes audit trail; reuses the existing service + the existing GET /api/v1/logs/admin-audit read route (no new endpoint).
    - `24.7` [24.7-c] — duplicate; **residual:** one record() call inside the payment-status transaction.
    - `24.10` [24.10-i] — duplicate; **residual:** one record() call inside the cancel transaction (guard half of 24.10-i is C8).

### C10 — Balance-due is the same scalar formula in list rows and the detail aggregate
*duplicate-requirement · recommend **cross-reference** · confidence medium*

- **Build first:** `24.1`
- **Shared build unit (build once):** A single source-of-truth for money figures: balance due = Order.total - Order.paid_amount, both read straight off the Order columns (there is NO separate 'centralized billing service'). The detail page's fee/subtotal breakdown is NOT part of this shared unit.
- **Effort saved:** Modest — agreeing that both surfaces read Order.total/paid_amount as the authoritative money source avoids two divergent balance calculations. The detail breakdown remains its own build.
- **Evidence:** schema.prisma:1573 Order.paid_amount 'Running sum ... bumped by webhook'; codebase_map: 'No separate centralized billing service' (pricing is in-process cart-pricing.service.ts)
- **Members:**
    - `24.1` [24.1-f, 24.1-g, 24.1-n] _(owner)_ — duplicate; **residual:** per-row Item Total (Order.total) + Balance Due (total - paid_amount) in the list projection — two scalar columns. 24.1-n's prescribed 'centralized billing service' component does not exist (Partial); figures come straight off Order columns.
    - `24.6` [24.6-o] — shares-logic; **residual:** MOSTLY SEPARATE WORK — the detail breakdown (Items Subtotal, Fees, Subtotal, Order Total, Balance Payable, Total Payable) is a richer aggregation over OrderItem + fees that the list does NOT compute. The ONLY genuinely shared part is the Order Total / Balance scalars off Order.total/paid_amount. Treat as cross-reference (agree on the authoritative source), not a reused computation.

### C11 — Template email dispatch (MailerService.sendFromTemplate) reused across action emails
*duplicate-requirement · recommend **build-once-reuse** · confidence medium*

- **Build first:** `24.5`
- **Shared build unit (build once):** MailerService.sendFromTemplate (renders a NotificationTemplate, sends via SendGrid, writes NotificationLog) — already built and proven
- **Effort saved:** No story builds an email-sending mechanism; each reuses the existing template mailer + NotificationLog. Review focuses on which template/recipient each uses, not on send infrastructure.
- **Evidence:** background-worker-service/src/notification/mailer.service.ts:88 sendFromTemplate VERIFIED; reused by lead-notification/low-balance/daily-summary crons
- **Members:**
    - `24.5` [24.5-i, 24.5-j] _(owner)_ — shares-logic; **residual:** resend-confirmation and resend-portal-password each pick a fixed template — distinct endpoints, same mailer. (24.5-j password-reset may also route through an existing auth reset path; either way no new send infra.)
    - `24.6` [24.6-r] — shares-logic; **residual:** send-email dispatches an admin-SELECTED template (dropdown from notification-template list) — distinct selection UI, same mailer.
    - `24.11` [24.11-c] — shares-logic; **residual:** cancellation/refund email — same mailer; needs the trigger_event + template seeded (see C4).
    - `24.15` [24.15-c, 24.15-d] — shares-logic; **residual:** the cron calls the same mailer with upcoming/overdue templates — same dispatch primitive; the TRIGGERING (24.15-a/b/e/f/g) is Blocked on a manual-pay mark-as-Paid path, NOT a mailer concern.

### C12 — InventoryReservation release helper reused by Order Cancel and Move-Show
*duplicate-requirement · recommend **build-once-reuse** · confidence medium*

- **Build first:** `24.12`
- **Shared build unit (build once):** A net-new admin-side 'release reservations by order_id' helper — Prisma updateMany {order_id, status:committed} -> {status:released, released_at} (mirroring webhook.service.ts:2762-2765, which lives in external-api-service and is NOT reachable from admin) — plus reuse of the existing InventoryService.commitForCart (FOR UPDATE lock) for the move re-commit
- **Effort saved:** The committed->released release logic is written ONCE in admin-backend-api and reused by both the cancel and move-show transactions, instead of two independent release implementations. Avoids two divergent reservation-state mutations.
- **Evidence:** admin/inventory/inventory.service.ts:104 commitForCart (FOR UPDATE) + :53 getAvailability, NO release method; release pattern proven at external-api-service/src/modules/webhook/services/webhook.service.ts:2762-2765 (committed->released by order_id); endpointCatalog POST .../cancel (24.12 release reqs) and POST .../move-show (24.13-i atomic release+commit)
- **Members:**
    - `24.12` [24.12-b, 24.12-c, 24.12-f] _(owner)_ — shares-logic; **residual:** owner of the admin release helper; cancel calls release(order_id) for booth + non-booth committed lines inside the cancel transaction. Auto Social-Tables release (24.12-d) stays Blocked.
    - `24.13` [24.13-e, 24.13-i] — shares-logic; **residual:** move-show calls the SAME release helper for the source show, then re-maps each OrderItem to the destination ShowProduct and re-commits via InventoryService.commitForCart under FOR UPDATE. Net-new to 24.13: the line re-mapping + destination validation orchestration. Included-product availability (24.13-f) stays Partial (default-included lines are excluded from inventory commit).

### C13 — PaymentTransaction installment row projection shared by Details, Payments, and Payment-Plan reads
*shared-implementation · recommend **cross-reference** · confidence low*

- **Build first:** `24.8`
- **Shared build unit (build once):** A single PaymentTransaction -> installment-row mapper (Invoice #, date, status, amount due, order total, amount paid, + next-installment derivation) reused by the three read surfaces
- **Effort saved:** Build the PaymentTransaction->row projection and next-installment derivation once; three read surfaces reuse it instead of three divergent installment mappers. Endpoints stay distinct (per catalog) — this is reuse of the projection, not a fold.
- **Evidence:** endpointCatalog notes on GET .../payments: 'Overlaps in data with GET .../payment-plan but kept distinct'; PaymentTransaction is the single installment ledger (one row per installment with amount, due_date, status, paid_at, invoice_id) per 24.8 summary
- **Members:**
    - `24.8` [24.8-a, 24.8-h] _(owner)_ — shares-logic; **residual:** owner — the full payment-plan read with Unallocated Balance + 60/30-day warnings; the base installment row projection is the shared piece. Missing Payment Type / Payment Memo columns keep 24.8-a Partial.
    - `24.7` [24.7-a, 24.7-e] — shares-logic; **residual:** the Payments screen reuses the installment row projection but focuses on status/method; catalog deliberately keeps GET .../payments a DISTINCT endpoint from GET .../payment-plan. No endpoint merge — only the row mapper is shared.
    - `24.6` [24.6-p, 24.6-q] — shares-logic; **residual:** the detail aggregate embeds the payment-plan reference + next-installment amount/date (24.6-q), derivable from the same PaymentTransaction projection (next = earliest unpaid by due_date). 24.6-p stays Partial (cart_id linkage caveat).


## Order History

**Build-first owners (2):** 13.2, 13.3 — building these covers the shared work in 6 clusters.

### C1 — Order History (13.1) is a full subset of Order Listing Table (13.2)
*subsumed-story · recommend **fold** · confidence high*

- **Build first:** `13.2`
- **Shared build unit (build once):** GET /orders — the single canonical company-scoped, paginated exhibitor order-listing endpoint (reuses ppl.service listOrderHistory pagination + findExhibitorCompanyOrFail company scoping + purchased-booths buildOrderGroup multi-show grouping)
- **Effort saved:** Eliminates a second listing endpoint/route (the invented GET /order-history was correctly removed) plus a duplicate page-level review of ownership/completeness/empty-state. 13.1 needs zero separate implementation and zero separate QA pass once 13.2 is verified.
- **Evidence:** Endpoint catalog GET /orders stories=[13.1,13.2]; reuses ppl.service listOrderHistory (exhibitor-backend-api/src/ppl/services/ppl.service.ts:916 controller / service) + findExhibitorCompanyOrFail company scoping (ppl.service.ts) + buildOrderGroup grouping (exhibitor-backend-api/src/purchased-booths/purchased-booths.service.ts:147)
- **Members:**
    - `13.1` [13.1-a, 13.1-b, 13.1-c, 13.1-d, 13.1-e, 13.1-f] — subset; **residual:** none. Verified 1:1: 13.1-a (list all orders in one place) + 13.1-d (past AND current completeness) = 13.2-a; 13.1-b + 13.1-c (own-orders ownership + backend enforcement) = 13.2-j (also tracked as cross-cutting in C4); 13.1-e (empty state) is the one formerly-unique 13.1 requirement and was already folded into 13.2 as 13.2-m; 13.1-f (order-level actions, verdict Out-of-Scope, text explicitly 'Refer User Story Order Listing Table') maps to 13.2's per-row View/Invoice/Pay-availability actions (13.2-f/13.2-g/13.2-h). 13.1 introduces no independent route or logic.
    - `13.2` [13.2-a, 13.2-j, 13.2-m] _(owner)_ — subset; **residual:** 13.2 is the primary owner and is built in full; nothing extra is owed to 13.1 once 13.2 (incl. 13.2-m empty state) is built and verified.

### C2 — View action (13.2-f) and the Order Details page (13.3) share the same details endpoint
*shared-implementation · recommend **cross-reference** · confidence high*

- **Build first:** `13.3`
- **Shared build unit (build once):** GET /orders/:orderId — the read-only ownership-scoped order-details aggregate endpoint
- **Effort saved:** Avoids speccing/building a separate 'order summary' endpoint for the 13.2 View action; one details endpoint is reviewed once and 13.2-f is marked delivered-by-13.3.
- **Evidence:** Endpoint catalog GET /orders/:orderId stories=[13.2,13.3], 13.2-f mapped to it; underlying data written by cart checkout write-path (exhibitor-backend-api/src/cart/services/cart.service.ts:1265 + cart/helpers/cart.helpers.ts:33 materializeCartToOrder)
- **Members:**
    - `13.2` [13.2-f] — shares-endpoint; **residual:** none on the backend — the View action navigates a listing row to GET /orders/:orderId; building 13.3's details endpoint delivers 13.2-f entirely. Only the front-end row-to-detail wiring is outside API scope.
    - `13.3` [13.3-a, 13.3-b, 13.3-d, 13.3-e, 13.3-h, 13.3-i, 13.3-j, 13.3-k, 13.3-m, 13.3-n, 13.3-o, 13.3-p, 13.3-q, 13.3-r, 13.3-u, 13.3-x, 13.3-y, 13.3-z, 13.3-aa, 13.3-ab] _(owner)_ — shares-endpoint; **residual:** 13.3 owns the entire aggregate build (header/booth/add-on/sponsorship line items, financial summary, payment details + reconciliation, agreement acceptance). This is the substantive work; 13.2-f is a free rider on it. Recommendation is cross-reference, NOT fold, because 13.3 is a large independent story — only 13.2-f collapses into it.

### C3 — Invoice download endpoint shared by listing Invoice action and details Download-Invoice button
*shared-implementation · recommend **build-once-reuse** · confidence high*

- **Build first:** `13.2`
- **Shared build unit (build once):** GET /orders/:orderId/invoice — order-scoped invoice PDF (net-new order→Invoice resolution) reusing the existing ppl.service pdfkit renderer + S3 signed-URL path
- **Effort saved:** One invoice endpoint instead of two; single review of the order→Invoice resolution + pdfkit/signed-URL render serves both the listing button and the details-page button (and any split-installment invoice variants).
- **Evidence:** Endpoint catalog GET /orders/:orderId/invoice stories=[13.2,13.3]; existing renderer downloadInvoicePdf at exhibitor-backend-api/src/ppl/controllers/ppl.controller.ts:1038 (delegates to ppl.service) — keyed on invoiceId, so order→Invoice resolution is the only net-new piece. Invoice rows written by external-api webhook for cart-flow orders.
- **Members:**
    - `13.2` [13.2-g] _(owner)_ — shares-endpoint; **residual:** none beyond the shared endpoint — the listing Invoice action calls the same GET /orders/:orderId/invoice.
    - `13.3` [13.3-s, 13.3-ac] — shares-endpoint; **residual:** 13.3-s (Download Invoice button) is fully covered by the shared invoice endpoint. 13.3-ac is COMPOUND ('signed agreement AND invoice PDF downloadable') and only its invoice half is covered here; its signed-agreement half is served by the single-story GET /orders/:orderId/agreement (13.3-only, no cluster) and is itself Partial — only the captured signature image + acceptance metadata exist, no composed agreement document is generated. That agreement work is separate and not redundant.

### C4 — Company-ownership scoping + backend enforcement repeated across all three stories
*duplicate-requirement · recommend **build-once-reuse** · confidence high*

- **Build first:** `13.2`
- **Shared build unit (build once):** Company-ownership scoping guard/predicate (auth guard + company_id WHERE via findExhibitorCompanyOrFail) applied uniformly to every /orders* endpoint
- **Effort saved:** Design and security-review the ownership rule once; the other stories assert reuse plus a per-route guard test rather than re-deriving the rule.
- **Evidence:** findExhibitorCompanyOrFail pattern in exhibitor-backend-api/src/ppl/services/ppl.service.ts (used at lines 93,148,217,248,301,...); applied per-route on GET /orders and /orders/:orderId per catalog notes
- **Members:**
    - `13.1` [13.1-b, 13.1-c] — duplicate; **residual:** none — fully delivered by the listing endpoint's scoping (= 13.2-j); consistent with the C1 fold.
    - `13.2` [13.2-j] _(owner)_ — duplicate; **residual:** Canonical owner of the scoping predicate on GET /orders. Designing and security-reviewing it once is the substantive work.
    - `13.3` [13.3-x] — duplicate; **residual:** Must apply the SAME predicate to GET /orders/:orderId AND to both sub-routes (/invoice, /agreement) — reuse the helper, but each new route still needs the guard wired plus a per-route 'wrong-company returns 404/403' test. Not zero, but no new logic.

### C5 — Derived order-level payment-status (display) reused by listing rows and details header
*shared-implementation · recommend **build-once-reuse** · confidence medium*

- **Build first:** `13.2`
- **Shared build unit (build once):** A NET-NEW read-time order-level payment-status derivation mapping {status, paid_amount, paid_in_full_at, + installment/overdue rollup} → Paid in Full / Partially Paid / Unpaid. Built once and consumed by both the listing row and the details header.
- **Effort saved:** Write and test the Paid/Partially/Unpaid derivation (incl. overdue rollup) once; the details header consumes the identical computed field instead of re-implementing it.
- **Evidence:** external-api computeNewOrderStatus (external-api-service/src/modules/webhook/services/webhook.service.ts:2245) is only a WRITE-PATH producing the stored Order.status (completed/partially_paid) and does NOT handle overdue — it is an input, not the reused unit. paid_in_full_at written at webhook.service.ts:2103. The shared read-time display derivation is net-new; hence medium confidence.
- **Members:**
    - `13.2` [13.2-c, 13.2-e] _(owner)_ — shares-logic; **residual:** Owner of the derivation. 13.2-e (an Overdue installment plan must roll the order up to not-fully-paid) lives inside the same computation and requires reading PaymentTransaction.due_date/status — this is the substantive part and is NOT covered by any existing write-path.
    - `13.3` [13.3-a] — shares-logic; **residual:** none on the status computation — the details header 'Payment Status (e.g. Paid in Full)' is the identical derived value (including the overdue rollup). 13.3-a's other header fields (Order ID, date/time) are trivial passthroughs and not part of this shared unit.

### C6 — All monetary figures read from the billing-owned Order record (shared data-source principle)
*duplicate-requirement · recommend **cross-reference** · confidence low*

- **Build first:** `13.2`
- **Shared build unit (build once):** Architectural decision/data-access pattern: read monetary figures (Order.total, total_savings, paid_amount, fees, coupon) directly from the billing-owned Order record rather than recomputing client-side. Not a single computed value.
- **Effort saved:** Settle the 'do not recompute totals; read the billing-owned Order figures' decision once so list and details cannot diverge. Small but real — it is an architectural alignment, not a reusable computation.
- **Evidence:** Order monetary fields (total, total_savings, paid_amount, fees, coupon_amount) written by cart checkout write-path (exhibitor-backend-api/src/cart/helpers/cart.helpers.ts:33 materializeCartToOrder) + flipped by external-api webhook; same Order record read by both stories. No 'centralized billing service' module exists (codebase map) — 'billing' = the Order record.
- **Members:**
    - `13.2` [13.2-k] _(owner)_ — shares-logic; **residual:** Owner of the 'Total Amount comes from billing' rule on the listing row — specifically the per-order Order.total figure.
    - `13.3` [13.3-n, 13.3-o, 13.3-z] — shares-logic; **residual:** These are DIFFERENT fields from 13.2-k's Order.total: 13.3-n = total_savings, 13.3-o = paid_amount (Total Paid), 13.3-z = full reconciliation across subtotal/fees/savings/total-paid. Only the 'read from the Order record, do not recompute' principle is shared — the breakdown, the distinct fields and the reconciliation check are all genuine separate work, not redundant.


## Inter-Story & Cross-Epic Dependencies (blockers, sequencing, external providers)

Complements the build-consolidation clusters above. Where the clusters answer *"what shared build
unit does this story reuse,"* this section answers *"what must ship elsewhere before this story's
requirement can be delivered"* — cross-epic blockers (with Jira/sprint status) and requirements
that turned out already-delivered or not-deliverable. **Source of truth remains each story's
feasibility `.md`; keep the Jira/sprint status rows current.**

**Status legend:** ✅ available · 🔵 Blocked (a real story would unblock) · ⛔ Not Deliverable (no data/story) · ⁇ open question · 🔗 already delivered / reuse.

_Last updated 2026-07-01 from the 13.3 Order Details analysis; OM Epic-24 dependency rows marked ⁇ are feasibility-level only, not yet deep-analyzed._

### Order History ↔ Order Management

| Consumer (story · req) | Depends on | Provider (story · Jira) | Status | Notes |
|---|---|---|---|---|
| **13.3-t** Payment Schedule | salesperson plan **written + linked to Order**, then shown to exhibitor | OM **24.8 Payment Plan Management** (producers SBE-1109/1111/1112, In Progress **SBE Sprint 5**); exhibitor visibility [SBE-1154](https://unifiedinfotech.atlassian.net/browse/SBE-1154) (backlog/To Do, Prantik Saha) | 🔵 | `CartPaymentScheduleEntry`/`CartPaymentPlan` is cart-only, **not linked to an Order** — the real blocker. Option (b): `/payments/checkout` split already writes a per-installment schedule in `PaymentTransaction` (deliverable now). SBE-1132 "Payment Plan Management" → 24.8. |
| **13.3** Order Details aggregate | shared order-aggregation shape + PaymentTransaction projection | OM **24.6 Order Details** (admin) | ⁇ | Both aggregate one order; overlaps OM-C13 (installment projection). Confirm reuse when 24.6 is analyzed. |
| **13.2 / 13.3** lifecycle display (canceled/refunded/paid_amount) | admin **write-side** that mutates order state | OM **24.9** Refund, **24.10** Cancel, **24.12** Booth Release, **24.13** Move-Show (see OM-C2/C3/C12) | ⁇ | OH is read-only and *reflects* states these OM stories write. Not a build blocker; OH display correctness depends on their field semantics. |

### External-epic blockers gating Order History

| Consumer (req) | Depends on | Provider (story / Jira) | Status | Notes |
|---|---|---|---|---|
| **13.3-l** Gift Certificate line | redemption producer (write `GiftCertificateRedeem`) | Story **12.4 "Gift Cart Redemption"** — [Exhibitor Store App](https://unifiedinfotech.atlassian.net/wiki/spaces/SBE/pages/3858137106/SBE+-+Exhibitor+Store+Application) (search "Gift Cart Redemption"); [SBE-1069](https://unifiedinfotech.atlassian.net/browse/SBE-1069) (Epic, To Do, unassigned) | 🔵 | Zero producer today; omit line via conditional display until 12.4 ships. |
| **13.3-g** Booth Upgrade details | upgrade captured/linked on the order | **"Booth Upgrade"** story — [Exhibitor Store App](https://unifiedinfotech.atlassian.net/wiki/spaces/SBE/pages/3858137106/SBE+-+Exhibitor+Store+Application) (search "Booth Upgrade" / "Upgrade Booth") | 🔵 | Upgrades modelled as fresh purchases of the price difference; no upgrade detail on the original order. |
| **13.3-c** Booth Number | stall-number assignment source, order-joined | none found. Lead: **"Booth Sign Print Page"** — [Admin Panel Page 2](https://unifiedinfotech.atlassian.net/wiki/spaces/SBE/pages/3984654414/SBE+-+Admin+Panel+Page+2) (company+show level, not order) | ⛔ | Assigned externally after purchase (`notification-template.seeder.ts:668`); no schema column, no order link. |
| **13.3-f** Booth Type (Std/Premium/Corner) | booth-type classification attribute | no story; data absent (`ProductType` = family only) | ⛔ | Classification doesn't exist anywhere. Open question: required, or BA artifact? |
| **13.3-w** Onsite Contact | `OnsiteBoothContact` populated **and** order-linked | **[SBE-1169 "View Onsite Boot Contact"](https://unifiedinfotech.atlassian.net/browse/SBE-1169)** (To Do, **Sprint 5**, Ritam) + producer **[SBE-1165 "Onsite Booth Contacts Management"](https://unifiedinfotech.atlassian.net/browse/SBE-1165)** (backlog, Manish); Edit SBE-1171 (Sprint 5). Confluence: [Exhibitor Store App](https://unifiedinfotech.atlassian.net/wiki/spaces/SBE/pages/3858137106/SBE+-+Exhibitor+Store+Application) | 🔵 | No producer today; keyed `(company_id, show_id)` with no Order FK. The Confluence Edit story intends **per-order** onsite contact, so those stories add the producer **and** the order-linkage. |

### Already-delivered / reuse — reconciles cluster assumptions

| Story · req | Reuse target (already built) | Status | Notes |
|---|---|---|---|
| **13.3-v / -ac** (agreement half) | `GET /agreement/signed/:orderId/download` (`agreement.controller.ts:154` → `buildSignedBoothContractDocx`) | 🔵 confirm | Composed terms+signature DOCX endpoint **exists in code** (ownership-scoped) — this **corrects** the feasibility "Partial" verdict and the OH-C3 note "no composed agreement document is generated." BUT **Blocked pending team confirmation of completion**: the code was **authored by Kshitiz** (git blame — controller route merged to dev, service still changing Jun 29) under [SBE-862 Exhibitor Agreement & Checkout Review](https://unifiedinfotech.atlassian.net/browse/SBE-862) / [SBE-869 Signed Agreement Storage](https://unifiedinfotech.atlassian.net/browse/SBE-869) (both In Progress, active **SBE Sprint 5**) — confirm completion with him. Separately [SBE-1158 "Download Agreement Option"](https://unifiedinfotech.atlassian.net/browse/SBE-1158) (Prantik, backlog/To Do, not started) may be **superseded** by that work — reconcile with the team. Reuses the existing endpoint (no new `/orders/:orderId/agreement` route). Caveat: DOCX not PDF. |
| **13.2 / 13.3-s** Invoice PDF | **deferred by both** — no product-order renderer (pdfkit `ppl.service` is subscription/Invoice-shaped) | 🔵/⁇ | **Updates OH-C3:** the invoice endpoint was NOT built with 13.2 (deferred pending A-vs-B: generate from `Order`+`OrderItems` vs serve persisted `Invoice` rows). 13.3 also defers. Open decision inherited. |
| **13.3** booth section | `purchased-booths.service.ts` (Jira SBE-1174 / SBE-1065 "Upcoming Purchased Booths and Sponsorship") | 🔗 | Existing `Order → orderItems(booth) → product/showProduct → show` join; mirror it, don't re-derive. |
| **13.3** read derivations | 13.2 orders module (`deriveOrderPaymentStatus`/`deriveIsOverdue`/`deriveCanPay`/`buildOrderShows`) | 🔗 | See OH-C5; 13.3 adds `GET /orders/:orderId` to the same module. |

### Maintenance
- Update the Jira/sprint status cells when tickets move; keep Confluence citations as **link + heading to search** (no bare page ids).
- When an OM Epic-24 story is deep-analyzed, replace its ⁇ rows with verified dependencies.
- This section lives outside the GDrive-synced `order_history/` & `order_management/` folders, so it is dev-facing only.

