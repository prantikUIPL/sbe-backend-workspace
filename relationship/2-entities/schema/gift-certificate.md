# GiftCertificate (+ Purchase + Redeem) — schema view

> Detailed schema for the **[GiftCertificate](../gift-certificate.md)** trio (template + purchase + redeem). The card has the mental model; this is the column-level reference. Authoritative source: [`schema.prisma:2512`](../../../admin-backend-api/prisma/schema.prisma#L2512) (`admin-backend-api` — source of truth).

## Diagram (entities + typed columns + relations)
![GiftCertificate schema diagram](gift-certificate.svg)

*Relation labels carry cardinality and `onDelete`. Crow's-foot notation: `||`=exactly one, `o{`=zero-or-many, `o|`=zero-or-one.*

## Data dictionary

### GiftCertificate (`gift_certificates`, [L2512](../../../admin-backend-api/prisma/schema.prisma#L2512))
The reusable **template**.

| Column | Type | Key | Null | Meaning |
|---|---|---|---|---|
| `id` | int | PK | no | Surrogate key |
| `name` | varchar(255) | UK | no | Template name (unique) |
| `status` | enum `GiftCertificateStatus` | — | no | `active` \| `inactive`; default `inactive` |
| `amount` | decimal(10,2) | — | no | Face value |
| `validity_in_months` | int | — | no | Lifetime applied to each purchase's expiry |
| `created_at` / `updated_at` | timestamptz | — | no | Timestamps |

### GiftCertificatePurchase (`gift_certificate_purchases`, [L2528](../../../admin-backend-api/prisma/schema.prisma#L2528))
An **instance** a Company bought, with a drawable balance.

| Column | Type | Key | Null | Meaning |
|---|---|---|---|---|
| `id` | int | PK | no | Surrogate key |
| `uuid` | char(6) | UK | no | 6-digit redemption code (exactly 6 chars) |
| `gift_certificate_id` | int | FK→GiftCertificate | no | Template (restrict — can't delete a bought template) |
| `amount` | decimal(10,2) | — | no | Purchased face value |
| `remaining_amount` | decimal(10,2) | — | no | Running balance after redemptions |
| `company_id` | int | FK→[Company](company.md) | no | Buyer (cascade) |
| `expire_at` | timestamptz | — | no | `created_at + validity_in_months` |
| `created_at` / `updated_at` | timestamptz | — | no | Timestamps |

### GiftCertificateRedeem (`gift_certificate_redeems`, [L2547](../../../admin-backend-api/prisma/schema.prisma#L2547))
Applying part of a purchase's balance to an **Order**.

| Column | Type | Key | Null | Meaning |
|---|---|---|---|---|
| `id` | int | PK | no | Surrogate key |
| `gift_certificate_id` | int | FK→GiftCertificate | no | Template (restrict) |
| `gift_certificate_purchase_id` | int | FK→GiftCertificatePurchase | no | Purchase drawn down (restrict) |
| `order_id` | int | FK→[Order](order.md) | no | Order the balance is applied to (**Restrict** — can't delete an order with a redemption) |
| `company_id` | int | FK→[Company](company.md) | no | Redeemer (cascade) |
| `amount` | decimal(10,2) | — | no | Amount applied (always positive; direction is read from `type`, never the sign) |
| `remaining_amount` | decimal(10,2) | — | no | Purchase balance after this row |
| `type` | enum `GiftCertificateRedeemType` | — | no | **(SBE-1179)** `expense` (checkout draw-down) \| `refund` (admin cancel/refund restore); default `expense` |
| `created_at` / `updated_at` | timestamptz | — | no | Timestamps |

## Relations
| From → To | Cardinality | onDelete | Meaning |
|---|---|---|---|
| GiftCertificate → GiftCertificatePurchase | 1→N | Restrict | Template sold as purchases |
| GiftCertificate → GiftCertificateRedeem | 1→N | Restrict | Template referenced by redemptions |
| GiftCertificatePurchase → [Company](company.md) | N→1 | Cascade | Buyer |
| GiftCertificatePurchase → GiftCertificateRedeem | 1→N | Restrict | Balance drawn down by redemptions |
| GiftCertificateRedeem → [Order](order.md) | N→1 | **Restrict** | Order the redemption applies to (blocks order delete) |
| GiftCertificateRedeem → [Company](company.md) | N→1 | Cascade | Redeemer |

## Indexes
GiftCertificate: unique on `name`. GiftCertificatePurchase: unique on `uuid`. GiftCertificateRedeem: **no uniqueness** — indexed on `order_id` and `(order_id, type)`. **(SBE-1179)** an order carries one `expense` redemption plus zero or more `refund` restorations (admin cancel/partial refunds), so the former `@@unique([order_id])` was dropped.

---
*Regenerate diagram: `mmdc -i gift-certificate.mmd -o gift-certificate.svg -b white -p pptr.json -c mermaid-config.json`*
