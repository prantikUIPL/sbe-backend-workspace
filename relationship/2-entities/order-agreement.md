# OrderAgreement

## What it is
The **immutable signature record** for one [Order](order.md): who signed, when, their signature data, the terms version they accepted, plus IP and user-agent as legal evidence. Written once at checkout and **never updated or deleted** in normal operation.

## Its neighborhood
![OrderAgreement ego diagram](ego/order-agreement.svg)

## Relationships, read as sentences
- An OrderAgreement **belongs to** exactly one **[Order](order.md)** (1→1, unique `order_id`, cascade).
- It **records a snapshot of** the terms that came from an **[Agreement](agreement.md)** template — but note this is a *value snapshot* (`terms_version`), **not an FK**.

## Why it matters / gotchas
- **One agreement per order**, enforced by the unique `order_id`.
- It is **immutable by policy** for legal compliance — treat it as append-only. There's no FK to [Agreement](agreement.md) precisely so that re-versioning the template never alters historic signatures.

## Next
[Order](order.md) · [Agreement](agreement.md)
