# PaymentMethod — schema view

> Detailed schema for the **[PaymentMethod](../payment-method.md)** entity. The card has the mental model; this is the column-level reference. Authoritative source: [`schema.prisma:963`](../../../admin-backend-api/prisma/schema.prisma#L963) (`admin-backend-api` — source of truth).

## Diagram (entity + typed columns + relations)
![PaymentMethod schema diagram](payment-method.svg)

*Relation labels carry cardinality and `onDelete`. Crow's-foot notation: `||`=exactly one, `o{`=zero-or-many, `o|`=zero-or-one.*

## Data dictionary
| Column | Type | Key | Null | Meaning |
|---|---|---|---|---|
| `id` | int | PK | no | Surrogate key |
| `company_id` | int | FK→[Company](company.md) | no | Owning company (cascade) |
| `stripe_payment_method_id` | varchar(255) | UK | no | Stripe PaymentMethod (`pm_xxx`) |
| `stripe_customer_id` | varchar(255) | — | no | Stripe customer (`cus_xxx`) |
| `type` | varchar(50) | — | yes | Default `card` |
| `used_for` | enum `PaymentMethodUsedFor` | — | no | `PPL` \| `Order`; default `Order` |
| `cardholder_name` | varchar(255) | — | yes | Name on card |
| `brand` | varchar(50) | — | yes | Card brand (e.g. `visa`) |
| `last4` | varchar(4) | — | yes | Last four digits |
| `exp_month` | int | — | yes | Expiry month |
| `exp_year` | int | — | yes | Expiry year |
| `fingerprint` | varchar(255) | — | yes | Stripe fingerprint (duplicate detection) |
| `is_default` | boolean | — | no | Default card flag; default false |
| `deleted_at` | timestamptz | — | yes | **Soft delete only** |
| `created_at` / `updated_at` | timestamptz | — | no | Timestamps |

## Relations
| Related entity | Cardinality | onDelete | Meaning |
|---|---|---|---|
| [Company](company.md) | N→1 | Cascade | Owner |
| [CompanySubscription](company-subscription.md) | 1→N | SetNull (from subscription) | Subscriptions defaulting to this card |

## Indexes
No explicit `@@index`; unique on `stripe_payment_method_id`.

---
*Regenerate diagram: `mmdc -i payment-method.mmd -o payment-method.svg -b white -p pptr.json -c mermaid-config.json`*
