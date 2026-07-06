# Level 3 — Dense reference maps

The "for when you already know the pieces" layer. Each `.mmd` renders to a `.svg` beside it.

| File | What it shows |
|---|---|
| [00-order-surface-overview](00-order-surface-overview.svg) | Both surfaces (exhibitor + admin) over the one shared `Order` table. |
| [01-admin-order-lifecycle](01-admin-order-lifecycle.svg) | The admin operations an order flows through: list → details → edit/notes/pay/quick-actions/refund/cancel → canceled/refunded + email. |
| [02-exhibitor-order-flow](02-exhibitor-order-flow.svg) | The exhibitor path: login → listing → details (404 if not owned) → invoice. |
| [03-shared-units](03-shared-units.svg) | The U1–U20 shared build units (owning story → consumers). |
| [04-endpoint-catalog.md](04-endpoint-catalog.md) | Every route in both epics + the dropped/parked/OOS proposals. |
| [05-release-phasing](05-release-phasing.svg) | The Phase-1 build/merge order (24.9 → … → 24.15) + the pre-merged stories. |

← Back to the [guide index](../README.md).
