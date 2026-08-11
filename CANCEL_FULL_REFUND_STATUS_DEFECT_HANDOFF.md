# Handoff — Cancelled + Fully-Refunded Orders Display as "Active (Payment Pending)"

> **Purpose.** This file is a self-contained brief for a developer (or a Claude Code agent) picking up a
> known defect in the SBE Order Management stack. It states the bug, the evidence that it *is* a bug rather
> than intended behaviour, the exact fix, everything the fix carries with it, and what NOT to do.
>
> **Author context:** written at handoff by the previous owner of Order Management / Order History
> (Prantik Saha). The stories involved are all DEV DONE and merged; this is a post-merge defect.

---

## 0. Verified against

| Repo | Branch | Commit | Date |
|---|---|---|---|
| `admin-backend-api` | `dev` | `299397d2` | 2026-08-11 |
| `external-api-service` | `dev` | `a9dd025` | 2026-08-11 |

**Line numbers in this document are accurate as of those commits and WILL drift.** Every code site below
also carries a `grep` command — use the grep, not the line number, to locate it. Re-verify the defect still
exists before writing any code; if someone has already fixed it, stop and close the ticket.

---

## 1. TL;DR

Cancelling an order with a full refund leaves it displaying as **"Active (Payment Pending)"** on the admin
Order Details page, instead of **"Cancelled (Full Refund)"**.

The cause is **not** in the display code. The refund engine overwrites `Order.status` from `canceled` to
`refunded` *after* the cancel transaction has committed, destroying the marker the display logic depends on.

**The fix is a two-line, two-repo guard: make `canceled` sticky against the refund-status derivation.**
No display-code change, no schema change, no migration.

---

## 2. Background — the two decisions that collide

Both were made deliberately at the same gate; each is correct in isolation.

**Story 24.6 decision D1** (Order Details status taxonomy). The client's Order Status sheet enumerates
exactly six display values and has **no "Refunded" top-level status**. So `status_display` is *derived*, not
stored — no enum migration. Refunds are expressed as **qualifiers on a cancelled order**, computed by
arithmetic over the 24.9 refund ledger. Quoting the decision verbatim from
`order_management/24.6-order-details/24.6 - Order Details.md`:

> Qualifiers are pure arithmetic over 24.9's refund ledger: Never Paid (paid=0) / No Refund (paid>0,
> refunded=0) / Partial (0<refunded<paid) / Full (refunded=paid). API returns stored `status` + derived
> `status_display`. **BA note:** spec has no standalone "Refunded" top-level — a refund without cancel stays
> Active(…); stored `failed` maps to Active (Payment Pending).

**Story 24.9 decision D1** (refund state). `OrderStatus.refunded` is derived at write time: when every
*settled* installment is fully refunded, the order flips to `refunded`.

The BA note above reasoned about *"a refund without cancel"*. Nobody reasoned about **a cancel followed by a
full refund** — which is exactly what `refund_type: full` produces on the happy path, because 24.10 runs the
refund *after* the cancel transaction commits.

---

## 3. The mechanism

### 3.1 Cancel runs the refund after its own transaction commits

`POST /api/v1/orders/:id/cancel?confirm=true` with `{ refund_type: "full", reason, ... }`:

1. **Cancel tx commits** — `Order.status → canceled`, `scheduled`/`failed` installments cascade to
   `canceled`, inventory reservations released, gift certificate restored, audit written.
2. **Then** the refund legs run — delegated wholesale to 24.9's `createRefund`
   (`{ suppressNotification: true }`, so only the `order_canceled` email goes out).

The refund cannot run inside the cancel transaction because it makes Stripe HTTP calls. This ordering is
intentional and documented in `order-cancel.service.ts`.

```bash
grep -n "issueCancellationRefund" admin-backend-api/src/admin/orders/services/order-cancel.service.ts
```

### 3.2 The refund derivation overwrites `canceled`

`admin-backend-api/src/admin/orders/services/order-refund.service.ts` (~L925–939):

```bash
grep -n "deriveOrderRefundedStatus" admin-backend-api/src/admin/orders/services/order-refund.service.ts
```

```ts
if (areAllSettledTransactionsRefunded(settled)) {
  await tx.order.updateMany({
    where: { id: orderId, status: { not: OrderStatus.refunded } },   // ← excludes only `refunded`
    data: { status: OrderStatus.refunded },
  });
}
```

The guard excludes `refunded` but **not** `canceled`. So a cancelled order that then gets fully refunded ends
as `status: refunded`.

### 3.3 The display logic has nothing to match on

`admin-backend-api/src/admin/orders/orders.helpers.ts` (~L297):

```bash
grep -n "export function deriveOrderStatusDisplay" admin-backend-api/src/admin/orders/orders.helpers.ts
```

```ts
if (status === OrderStatus.canceled) {
  // Never Paid / No Refund / Partial Refund / Full Refund — chosen by ledger arithmetic
} else if (status === OrderStatus.completed) {
  → "Active (Paid In Full)"
} else {
  → "Active (Payment Pending)"        // ← `refunded` lands here
}
```

`refunded` is neither `canceled` nor `completed`, so it falls into the catch-all. **That catch-all is
intentional** (per D1's BA note: `pending`, `partially_paid`, `failed`, and a standalone `refunded` all
legitimately read as Active). The bug is that the cancel case never gets to reach the `canceled` branch.

---

## 4. Evidence this is a defect, not spec drift

1. **`ORDER_STATUS_DISPLAY.cancelled_full_refund` is defined but unreachable in production.** The only flow
   that produces a full refund on a cancelled order is the same flow that renames the status.
2. **A passing unit test asserts a state production cannot reach.**
   `admin-backend-api/src/admin/orders/orders.helpers.spec.ts:640` —
   `it('canceled + refunded = paid → Cancelled (Full Refund)')`. The helper is provably correct in
   isolation; the composition never feeds it a `canceled` order.
3. **Requirement 24.6-b** explicitly lists `Cancelled (Full Refund, Manual Update)` as a required display
   value (Confluence Admin Panel page `3859742741`, section `#Order-Management`).
4. **The old behaviour was observed and recorded** during the original build's live smoke, in
   `order_management/OM_PHASE1_RELEASE_PLAN.md` (Phase 2 status): *"standalone $200 refund on canceled order
   → 2 legs succeeded, PTs refunded, **order derived canceled→refunded per D1**"*. It was noted; its display
   consequence was not followed through.
5. **The invariant already exists elsewhere.** Phase 2 of the same release made `canceled` **sticky** in
   external-api's `computeNewOrderStatus`, so a payment webhook can never resurrect a cancelled order. This
   fix applies that same, already-approved invariant to the two refund-status writers that were missed.

---

## 5. Reproduction

1. Seed / find a **product** order with at least one settled (paid) installment.
2. `POST /api/v1/orders/:id/cancel?confirm=true` with `{ "refund_type": "full", "reason": "test" }`.
3. Wait for the refund legs to settle (manual refunds settle synchronously; Stripe legs may settle via the
   `charge.refunded` webhook).
4. `GET /api/v1/orders/:id`.

**Observed:** `status: "refunded"`, `status_display: "Active (Payment Pending)"`.
**Expected:** `status: "canceled"`, `status_display: "Cancelled (Full Refund)"`.

Only the fully-successful path misreports. If a Stripe leg fails (`refund_failed`) or the refund is partial,
the order correctly stays `canceled` and displays `Cancelled (Partial Refund)` / `Cancelled (No Refund)`.

---

## 6. The fix

### Change 1 of 2 — `admin-backend-api`

`src/admin/orders/services/order-refund.service.ts`, inside `deriveOrderRefundedStatus` (~L935):

```diff
 await tx.order.updateMany({
-  where: { id: orderId, status: { not: OrderStatus.refunded } },
+  where: { id: orderId, status: { notIn: [OrderStatus.refunded, OrderStatus.canceled] } },
   data: { status: OrderStatus.refunded },
 });
```

### Change 2 of 2 — `external-api-service` (DO NOT SKIP)

`src/modules/webhook/services/webhook.service.ts`, inside `deriveOrderRefundedStatusTx` (~L4712):

```bash
grep -n "deriveOrderRefundedStatusTx" external-api-service/src/modules/webhook/services/webhook.service.ts
```

```diff
-await tx.order.update({
-  where: { id: orderId },
-  data: { status: OrderStatus.refunded },
-});
+await tx.order.updateMany({
+  where: { id: orderId, status: { notIn: [OrderStatus.refunded, OrderStatus.canceled] } },
+  data: { status: OrderStatus.refunded },
+});
```

Two notes on this one:

- It currently has **no status guard at all** — it overwrites unconditionally.
- `update` → `updateMany` is **required**: Prisma's `update` needs a unique where-clause and will not accept
  the extra status filter.

This is the `charge.refunded` twin derivation. Its own comment explains why it exists: *"dashboard-originated
refunds never touch the admin endpoint."* **If you fix only the admin side, the bug still occurs in
production** whenever a Stripe refund settles asynchronously via webhook — and your tests will pass.

### Confirmed: these are the only two writers

```bash
# across all five repos — should return exactly these two sites
grep -rn "status: OrderStatus.refunded" --include="*.ts" . | grep -v ".spec.ts"
```

---

## 7. What the fix produces

With `canceled` preserved, the existing qualifier arithmetic in `deriveOrderStatusDisplay` does the rest —
**no display code changes**:

| `Order.status` | Condition | `status_display` |
|---|---|---|
| `canceled` | `paid_amount <= 0` | Cancelled (Never Paid) |
| `canceled` | `refundedTotal <= 0` | Cancelled (No Refund) |
| `canceled` | `refundedTotal >= paid_amount` | **Cancelled (Full Refund)** ← now reachable |
| `canceled` | otherwise | Cancelled (Partial Refund) |
| `refunded` (standalone, no cancel) | — | Active (Payment Pending) — unchanged, per D1 |

`refundedTotal` counts **`succeeded`** refund rows only (`deriveRefundedTotal`); `pending` rows reserve cap
but do not count toward the display arithmetic.

---

## 8. Specs to update

Line numbers as of the commits in §0.

| File | Lines | Change |
|---|---|---|
| `admin-backend-api/src/admin/orders/services/order-refund.service.spec.ts` | 330, 556, 873, 934 | four assertions pin the exact where-clause `{ id: 42, status: { not: OrderStatus.refunded } }` → `{ notIn: [refunded, canceled] }` |
| `admin-backend-api/src/admin/orders/services/order-cancel.service.spec.ts` | 378, 493, 559, 624, 655 | assertions expecting `order_status: OrderStatus.refunded`; the ones modelling **cancel-with-full-refund** become `OrderStatus.canceled`. Read each case — not all five are the same scenario. |
| `external-api-service/src/modules/webhook/services/webhook.service.spec.ts` | ~4945, 5261, 5320 (+ the `not.toHaveBeenCalled` cases) | `tx.order.update` → `tx.order.updateMany` with the guard; the tx mock needs `updateMany` |
| `admin-backend-api/src/admin/orders/orders.helpers.spec.ts` | 607 | **LEAVE ALONE** — `refunded (not canceled) → Active (Payment Pending)` remains correct per D1 |

**New cases to add (both repos):**

- cancelled order + full refund → `Order.status` stays `canceled`
- an integration-level assertion that such an order yields `status_display === 'Cancelled (Full Refund)'`
- external: `charge.refunded` on an already-cancelled order does not flip it

---

## 9. Do NOT do these

| ❌ | Why |
|---|---|
| Add a `refunded → Cancelled (Full Refund)` branch to `deriveOrderStatusDisplay` | Breaks the case D1 explicitly accepted — a **standalone** refund with no cancellation would then falsely display as Cancelled |
| Change any display code at all | The helper is correct and unit-tested; the defect is on the write side |
| Add a `canceled` value to some new enum / migrate `OrderStatus` | D1 explicitly rejected enum extension ("stores what is derivable") |
| Decrement `Order.paid_amount` on refund | `paid_amount` is **GROSS** by decision D3 and is never decremented by a refund; net is derived at read time via `deriveNetPaid`. The only legitimate gross decrement in the system is 24.8's Mark-as-Unpaid |
| Fix admin only | See §6 Change 2 — the webhook twin will still clobber it |

---

## 10. Blast radius — checked, no action needed

| Consumer | Effect of the fix |
|---|---|
| `assertOrderMutable` (`order-payment-plan.service.ts`, ~L685) | none — treats `canceled` and `refunded` identically as terminal |
| 24.6 `PATCH /orders/:id` status gating | none — editable only while `pending`/`partially_paid`/`failed`; both blocked either way |
| exhibitor `NON_PAYABLE_ORDER_STATUSES` (`src/orders/orders.helpers.ts`) | none — set already contains both |
| admin PPL module (`ppl-order.service.ts`, `case OrderStatus.refunded`) | none — separate module, different flow |
| `POST /orders/:id/cancel` response `order_status` | now returns `canceled` instead of `refunded` — more truthful |
| `GET /orders/:id/refund-options` `order_status` | shows `canceled` |
| 24.1 order listing | returns raw `status`; cancelled+refunded orders now read `canceled` instead of `refunded` |

**Announce to FE + QA:** orders filtered by `status = refunded` will no longer include cancelled-and-fully-
refunded ones. That is the intended semantics (they are cancellations), but any saved filter or report
relying on the old behaviour must key off the refund ledger instead.

---

## 11. Docs to update with the fix

These currently record the old behaviour and will contradict the code:

- `order_management/OM_PHASE1_RELEASE_PLAN.md` — Phase 2 status block, the smoke line *"order derived
  canceled→refunded per D1"*. (This file is also copied into each of the 7 OM story subfolders — update the
  canonical one and re-copy, per the "one release = one plan" convention.)
- `order_management/24.6-order-details/24.6 - Order Details.md` + `.xlsx` — Implementation Status, 24.6-b row.
- `order_management/24.9-refund-management/24.9 - Refund Management.md` + `.xlsx` — D1 note on derived
  refund state.
- `order_management/24.10-order-cancellation/24.10 - Order Cancellation.md` + `.xlsx`.

⚠️ The `order_management/` and `order_history/` folders are **bidirectionally synced to Google Drive** (the
previous owner viewed/edited them as Google Sheets). Re-read a file before editing it; do not assume the
local copy is current.

Confluence page `3859742741` is **READ-ONLY** for engineering — flag any spec discrepancy to the BA, do not
edit the page.

---

## 12. Verification before shipping

1. **Scoped gates** — `npx eslint`, `npx tsc --noEmit`, `npx jest src/admin/orders` (admin) and the webhook
   suite (external). Run jest/tsc **from inside each repo directory** — running from the workspace root makes
   jest fall back to babel and produce spurious TS parse errors.
2. **Full pre-push gate** in both repos (`npm ci` → `prisma generate` → typecheck → lint → `test:cov` →
   `build`). There is a `scripts/pre-push-check-*.sh` per repo.
3. **Live smoke — strongly recommended, this touches three merged stories currently in QA.** Seed a paid
   split order, cancel with `refund_type: full`, then `GET /orders/:id` and assert
   `status === 'canceled' && status_display === 'Cancelled (Full Refund)'`. Also re-check that a
   **standalone** full refund (no cancel) still yields `status: 'refunded'` / `Active (Payment Pending)`.
   - Admin boots locally with `NODE_ENV=local` (any other value triggers an AWS-secrets bootstrap throw) and
     needs `ID_ENCRYPTION_KEY` injected inline if absent from `.env`.
   - Prisma 7 here uses the `client` engine + `PrismaPg` adapter — a bare `new PrismaClient()` throws; pass
     `{ adapter: new PrismaPg({ connectionString }) }`.
4. **CI** — Bitbucket Pipelines (workspace `unified-dev-cls-a`) runs gitleaks → lint/typecheck/test →
   SonarQube. If the gate goes red, confirm *which step* failed before assuming SonarQube, and fix only
   new-code issues your own change introduced (verify via git blame).

---

## 13. Process notes for this codebase

- Feature branches are cut from `dev`. Commit scope is the Jira ticket: `fix(SBE-xxxx): description`.
- **No AI/co-author trailers in commit messages.**
- `admin-backend-api` owns Prisma migrations; the other four repos use `db push` only. **This fix needs no
  migration.**
- Two PRs (admin + external), both into `dev`.
- This is a **post-DEV-DONE defect** across merged stories 24.6 (SBE-1130), 24.9 (SBE-1133) and 24.10
  (SBE-1134), all children of epic **SBE-1078**. It needs its **own bug ticket** — do not reopen the story
  tickets. QA twins (SBE-1546 / SBE-1549 / SBE-1550, assignee Rohit Gupta) were In QA Testing at handoff, so
  QA may raise this independently; check for an existing ticket first.

---

## 14. Open question for the BA (not blocking the fix)

The guard makes `canceled` win over `refunded`. That is correct for the spec's model, where "Cancelled" is
the outcome and the refund is a qualifier. But it means **order status alone can no longer distinguish
"cancelled and fully refunded" from "refunded"** in any future flow that needs that distinction — the fix
resolves it by privileging cancellation.

The more robust alternative is a durable `canceled_at` timestamp (or reading the cascade-cancelled
installments) so the display no longer infers cancellation from a mutable status field. That is a migration
across five repos plus an imperfect backfill from the audit log, and is only worth doing if the BA wants
cancellation to be a first-class fact rather than a status value.

**Recommendation: ship the guard now; raise `canceled_at` separately if the distinction matters.**

---

## 15. Where to read more

| Topic | Location |
|---|---|
| Ticket ↔ story ↔ status map for both order epics | `ORDER_EPICS_JIRA_CI_SNAPSHOT.md` (repo root) |
| Per-story requirements, verdicts, implementation status | `order_management/24.x-*/` and `order_history/13.x-*/` (`.md` + `.xlsx`) |
| The release these stories shipped in, incl. all design decisions D1–D7 | `order_management/OM_PHASE1_RELEASE_PLAN.md` |
| Cross-story shared units (the C13 installment mapper, label maps, etc.) | `order_management/OM_PHASE1_SHARED_UNIT_LEDGER.md` |
| Post-release reconciliation of delivered vs planned | `order_management/OM_PHASE1_DELIVERY_AUDIT.md` |
| API learning guide for the order surfaces | `orders-guide/` |
| Entity relationships | `relationship/` |
| Story workflow (plan → branch → build → gate → push → docs → Jira) | `STORY_IMPLEMENTATION_PROCESS.md` |
