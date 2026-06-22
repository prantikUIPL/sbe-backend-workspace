# Cart

## What it is
A **mutable proposal/contract** a sales rep (or exhibitor) builds for a Company across one or more shows. It's the working draft of a deal. On signature it converts into exactly **one** [Order](order.md). Carts are the origin of *product* orders only (subscriptions/PPL add-ons don't use carts).

## Its neighborhood
![Cart ego diagram](ego/cart.svg)

## Relationships, read as sentences
- A Cart **belongs to** one **[Company](company.md)** (N→1, cascade).
- A Cart **may have** an applied **[CouponCode](coupon-code.md)** (N→1, `SetNull`) and an assigned sales-rep **User** (`SetNull`).
- A Cart **contains** many **[CartItems](cart-item.md)** (1→N) and **holds stock via** many **InventoryReservation** rows (1→N).
- A Cart **converts to** at most one **[Order](order.md)** (1→1).
- A Cart **may have** a parent Cart (self-relation, `SetNull`) — reserved for the deferred Booth-Build upsell.

## Why it matters / gotchas
- **One cart → one order**, enforced by a unique `cart_id` on the Order side. Conversion is a one-way door.
- `created_by` + `created_by_type` is a **polymorphic owner** (admin / sales / exhibitor) with **no FK** by design.
- Money fields here (`subtotal`, `discount`, `total_savings`, `coupon_amount`) are the live draft totals; at signature they're frozen onto the Order.
- Soft-delete only (`deleted_at`).

## Next
[CartItem](cart-item.md) · [Order](order.md) · [CouponCode](coupon-code.md)
