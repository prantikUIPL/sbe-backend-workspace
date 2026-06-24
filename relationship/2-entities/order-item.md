# OrderItem

## What it is
A **frozen line on an [Order](order.md)** — a price/quantity snapshot taken at purchase time, so later catalog or price changes never rewrite order history. Each line points at exactly one of: a Product, a SubscriptionPlan, a PplAddonPackage, or a ShowProduct, depending on `item_type`.

## Its neighborhood
![OrderItem ego diagram](ego/order-item.svg)

📋 **Need the columns?** → [OrderItem schema view](schema/order-item.md) (typed fields + data dictionary)

## Relationships, read as sentences
- An OrderItem **is a line of** one **[Order](order.md)** (N→1, cascade).
- When `item_type = product`, it **references** a **[Product](product.md)** and usually the **[ShowProduct](show-product.md)** it came from (both `SetNull`).
- When `item_type = subscription`, it **references** a **SubscriptionPlan** (`SetNull`).
- When `item_type = ppl_addon`, it **references** a **[PplAddonPackage](ppl-addon-package.md)** (`SetNull`).
- An OrderItem **may nest under** a parent OrderItem (self-relation, `SetNull`) — add-on/fee lines group under their booth line.

## Why it matters / gotchas
- Exactly **one** of `product_id` / `subscription_plan_id` / `ppl_addon_package_id` is set per row — `item_type` is the discriminator.
- All catalog FKs are **`SetNull`**: deleting a product/plan/package never deletes order history, it just nulls the back-reference. The snapshot (`description`, `unit_price`, `amount`) survives.
- `lead_credits` carries PPL credits granted by subscription/add-on lines (0 for product lines).
- **Self-nesting tree:** `parent_order_item_id` lets add-on/fee lines sit under their booth line (self-relation, `SetNull`) — the frozen mirror of [CartItem](cart-item.md) nesting. Deleting a parent line nulls the child's pointer rather than removing it, so the snapshot survives.

## Next
[Order](order.md) · [Product](product.md) · [PplAddonPackage](ppl-addon-package.md)
