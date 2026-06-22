# Entity Relationships — SBE Platform

> How **orders, shows (events), payments, booths, and agreements** relate across the Small Business Expo platform, plus the supporting entities around them. Derived from the authoritative Prisma schema (`admin-backend-api/prisma/schema.prisma`, the source of truth across all five services).

Each diagram below is provided as a rendered **SVG** (also **PNG** in `diagrams/`) and as inline **Mermaid** source that renders directly on GitHub. Edit the `.mmd` files in `diagrams/` and re-render to update.

## Contents

- [The big picture](#the-big-picture)
- [Overview map](#overview-map)
- [Commerce lifecycle flow](#commerce-lifecycle-flow)
- [Detailed cluster diagrams](#detailed-cluster-diagrams)
- [How to regenerate](#how-to-regenerate)

## The big picture

Small Business Expo is a trade-show platform where exhibitor **Companies** buy booths and add-ons for specific **Shows** (events), and also subscribe to a Pay-Per-Lead (PPL) program. Almost every commercial record hangs off **Company**: it is the root that owns carts, orders, subscriptions, invoices, payments, payment methods, and leads. When a Company is deleted, that entire commercial footprint cascades away.

The end-to-end commerce flow is: a Company (usually via an assigned sales rep) builds a **Cart** of **ShowProducts** (a Product offered at a particular Show). On signature the Cart transitions into exactly one **Order**, which captures an immutable **OrderAgreement** signature, draws down stock via **InventoryReservation**, and is billed through one or more **Invoices** and charged through one or more **PaymentTransactions** (Stripe). Discounts come from **CouponCodes** applied at the cart, and legal terms come from **Agreement** templates referenced by Products.

There are two parallel order origins: **product orders** (born from a signed Cart, tied to ShowProducts) and **subscription / ppl_addon orders** (no cart; tied to a **CompanySubscription** and **SubscriptionPlan**). The `order_type` enum and the nullability of `cart_id` / `company_subscription_id` distinguish them.


## Overview map

Core entities and the principal links between them. Company is the root that nearly everything hangs off.

![Overview](diagrams/00-overview.svg)

<details>
<summary>Mermaid source</summary>

```mermaid
erDiagram
    COMPANY ||--o{ CART : "builds"
    COMPANY ||--o{ ORDER : "places"
    COMPANY ||--o{ COMPANYSUBSCRIPTION : "subscribes"
    COMPANY ||--o{ INVOICE : "billed via"
    COMPANY ||--o{ PAYMENTTRANSACTION : "charged via"
    SHOWS ||--o{ SHOWPRODUCT : "offers"
    PRODUCT ||--o{ SHOWPRODUCT : "sold as"
    UNIVERSALBOOTH ||--o{ UNIVERSALBOOTHSECONDARYIMAGE : "gallery"
    CART ||--o| ORDER : "signs into"
    CART ||--o{ CARTITEM : "contains"
    SHOWPRODUCT ||--o{ CARTITEM : "added as"
    COUPONCODE ||--o{ CART : "applied to"
    ORDER ||--|| ORDERAGREEMENT : "signed via"
    ORDER ||--o{ ORDERITEM : "snapshots"
    ORDER ||--o{ INVOICE : "billed by"
    ORDER ||--o{ PAYMENTTRANSACTION : "paid by"
    COMPANYSUBSCRIPTION ||--o{ ORDER : "renews via"
    AGREEMENT ||--o{ PRODUCT : "terms for"
    COMPANY {
        int id PK
        string name
        decimal lead_balance
    }
    SHOWS {
        int id PK
        string title
        int city_id FK
    }
    PRODUCT {
        int id PK
        string name
        int agreement_id FK
    }
    SHOWPRODUCT {
        int id PK
        int show_id FK
        int product_id FK
        decimal sales_price
    }
    UNIVERSALBOOTH {
        int id PK
        string name
    }
    CART {
        int id PK
        string cart_number
        int company_id FK
        int coupon_code_id FK
    }
    ORDER {
        int id PK
        string order_number
        string order_type
        int cart_id FK
        int company_subscription_id FK
    }
    ORDERAGREEMENT {
        int id PK
        int order_id FK
        datetime signed_at
    }
    ORDERITEM {
        int id PK
        int order_id FK
        string item_type
    }
    AGREEMENT {
        int id PK
        string type
        string version
    }
    INVOICE {
        int id PK
        string invoice_number
        int order_id FK
    }
    PAYMENTTRANSACTION {
        int id PK
        int order_id FK
        string status
    }
    COMPANYSUBSCRIPTION {
        int id PK
        int company_id FK
        string status
    }
    COUPONCODE {
        int id PK
        string code
        string coupon_type
    }
```

</details>

## Commerce lifecycle flow

The end-to-end path from browsing a show's products to a fully-paid, fulfilled order.

![Commerce flow](diagrams/01-commerce-flow.svg)

<details>
<summary>Mermaid source</summary>

```mermaid
flowchart LR
    A[Company browses Shows] -->|Show offers| B[ShowProducts: booths and addons]
    B -->|add line items| C[Cart with CartItems]
    C -->|apply| D[CouponCode discount]
    D --> C
    C -->|sign + accept terms| E[Order created]
    E -->|capture signature| F[OrderAgreement immutable]
    E -->|snapshot lines| G[OrderItems]
    E -->|consume stock| H[InventoryReservation vs ShowProduct]
    E -->|generate| I[Invoice + InvoiceLineItems]
    I -->|full or split| J[PaymentTransaction installments]
    J -->|Stripe webhook| K[StripeWebhookEvent dedup]
    K -->|mark paid| I
    E -->|optional| L[GiftCertificateRedeem]
    J -->|succeeded| M[Order completed]
    M -->|reserve booth space| N[Booth fulfillment at Show]
    M -->|subscription order| O[CompanySubscription active]
    O -->|grants| P[Lead credits + LeadTransactionLog]
```

</details>

## Detailed cluster diagrams

### Orders & checkout

`Cart` is the working proposal/contract. It belongs to a Company (`onDelete: Cascade`), may carry a parent cart (self-join, SetNull, for the deferred Booth-Build upsell), an applied `CouponCode` (SetNull), and an `assigned_sales_rep_id` User (SetNull). Its `CartItems` are booth/add-on/fee lines tied to a `ShowProduct`; CartItems nest under a parent CartItem (Cascade) so add-ons live under their booth line.

On signature the Cart becomes exactly **one** `Order` — enforced by the unique `cart_id` on `orders` (one-to-one, SetNull). The Order is the transactional core:
- **Company** many-to-one, Cascade.
- **OrderAgreement** one-to-one via unique `order_id` (Cascade) — an immutable, compliance-grade signature snapshot (signer name, signature data, IP/user-agent, terms_version). Never updated or deleted in normal operation.
- **OrderItem** one-to-many (Cascade) — price/quantity snapshots; each item points at exactly one of Product / SubscriptionPlan / PplAddonPackage / ShowProduct depending on `item_type`, all SetNull so catalog deletions don't orphan order history.
- **Invoice** one-to-many (SetNull) — an Order can produce several invoices (initial + renewals); invoices can even predate the Order (nullable `order_id`).
- **PaymentTransaction** one-to-many (Cascade) — one row for full payment, N rows for split installments.
- **InventoryReservation** one-to-many (SetNull) — stock consumed at signature.
- **sales_person_id** User many-to-one, **Restrict** — you cannot delete a sales user who has orders.

`InventoryReservation` is an append-only stock ledger: many-to-one to ShowProduct (Restrict — protects the ledger), Cart (Cascade), CartItem (Cascade), and Order (SetNull, cleared when an order is canceled to release the hold).

![Orders & checkout](diagrams/02-orders-checkout.svg)

<details>
<summary>Mermaid source</summary>

```mermaid
erDiagram
    COMPANY ||--o{ CART : "owns"
    COMPANY ||--o{ ORDER : "places"
    CART ||--o| ORDER : "signs into one"
    CART ||--o{ CARTITEM : "contains"
    CART ||--o{ CART : "parent of child"
    CART ||--o{ INVENTORYRESERVATION : "holds"
    CARTITEM ||--o{ CARTITEM : "nests addons"
    CARTITEM ||--o{ INVENTORYRESERVATION : "reserves"
    SHOWPRODUCT ||--o{ CARTITEM : "line for"
    SHOWPRODUCT ||--o{ INVENTORYRESERVATION : "stock from"
    ORDER ||--|| ORDERAGREEMENT : "signed via"
    ORDER ||--o{ ORDERITEM : "has"
    ORDER ||--o{ INVENTORYRESERVATION : "consumes"
    ORDER }o--o| COMPANYSUBSCRIPTION : "renews"
    ORDER }o--o| USER : "sales rep"
    SHOWPRODUCT ||--o{ ORDERITEM : "ordered as"
    CART {
        int id PK
        string cart_number
        int company_id FK
        int parent_cart_id FK
        int coupon_code_id FK
        string stage
        decimal total
    }
    CARTITEM {
        int id PK
        int cart_id FK
        int product_id FK
        int show_product_id FK
        int parent_cart_item_id FK
        decimal unit_price
    }
    ORDER {
        int id PK
        string order_number
        int company_id FK
        int cart_id FK
        int company_subscription_id FK
        int sales_person_id FK
        string order_type
        decimal total
    }
    ORDERAGREEMENT {
        int id PK
        int order_id FK
        string signer_first_name
        datetime signed_at
    }
    ORDERITEM {
        int id PK
        int order_id FK
        int show_product_id FK
        string item_type
        decimal unit_price
        int quantity
    }
    INVENTORYRESERVATION {
        int id PK
        int show_product_id FK
        int cart_id FK
        int cart_item_id FK
        int order_id FK
        int quantity
        string status
    }
    SHOWPRODUCT {
        int id PK
        int show_id FK
        int product_id FK
        int quantity
    }
```

</details>

### Payments & billing

This cluster tracks money against the Order. `PaymentTransaction` is one row per installment, carrying the Stripe PaymentIntent lifecycle, retry/backoff state, and `idempotency_key`. It is many-to-one to Order (Cascade) and Company (Cascade, denormalized for cron speed), and many-to-one to Invoice (SetNull, linked by webhook after the invoice exists).

`Invoice` is the billing document (dual Stripe + QuickBooks sync). It is many-to-one to Order (SetNull) and Company (Cascade), owns `InvoiceLineItem` rows (Cascade), and receives PaymentTransactions and LeadTransactionLog audit links (both SetNull).

The PPL subscription side: `SubscriptionPlan` defines tiers (Restrict on CompanySubscription — plans in use can't be deleted) and owns `SubscriptionPlanFeature` rows (Cascade). `CompanySubscription` is a Company's live subscription (Company Cascade, Plan Restrict, PaymentMethod SetNull) and is the hub for renewal Orders, distributed Leads, and `LeadTransactionLog` credit entries (all SetNull). `PaymentMethod` stores Stripe cards per Company (Cascade). `StripeWebhookEvent` is a standalone idempotency ledger with no relations. `CompanyStripeAccount` links a Company to its Stripe customer id (Cascade).

![Payments & billing](diagrams/03-payments-billing.svg)

<details>
<summary>Mermaid source</summary>

```mermaid
erDiagram
    COMPANY ||--o{ ORDER : "places"
    COMPANY ||--o{ INVOICE : "billed"
    COMPANY ||--o{ PAYMENTTRANSACTION : "charged"
    COMPANY ||--o{ PAYMENTMETHOD : "saves"
    COMPANY ||--o{ COMPANYSUBSCRIPTION : "subscribes"
    COMPANY ||--o| COMPANYSTRIPEACCOUNT : "linked to"
    ORDER ||--o{ INVOICE : "billed by"
    ORDER ||--o{ PAYMENTTRANSACTION : "paid by"
    ORDER ||--o{ ORDERITEM : "has"
    INVOICE ||--o{ INVOICELINEITEM : "breaks down"
    INVOICE ||--o{ PAYMENTTRANSACTION : "settled by"
    INVOICE ||--o{ LEADTRANSACTIONLOG : "audited by"
    SUBSCRIPTIONPLAN ||--o{ COMPANYSUBSCRIPTION : "subscribed as"
    SUBSCRIPTIONPLAN ||--o{ SUBSCRIPTIONPLANFEATURE : "lists"
    SUBSCRIPTIONPLAN ||--o{ ORDERITEM : "sold as"
    COMPANYSUBSCRIPTION ||--o{ ORDER : "renewed by"
    COMPANYSUBSCRIPTION ||--o{ LEADTRANSACTIONLOG : "credits"
    PAYMENTMETHOD ||--o{ COMPANYSUBSCRIPTION : "backs"
    PAYMENTTRANSACTION {
        int id PK
        int order_id FK
        int invoice_id FK
        int company_id FK
        int installment_number
        string status
    }
    INVOICE {
        int id PK
        int order_id FK
        int company_id FK
        string invoice_number
        string status
        decimal total
    }
    INVOICELINEITEM {
        int id PK
        int invoice_id FK
        decimal amount
    }
    SUBSCRIPTIONPLAN {
        int id PK
        string name
        string plan_type
        int lead_credits
    }
    SUBSCRIPTIONPLANFEATURE {
        int id PK
        int subscription_plan_id FK
        string name
    }
    COMPANYSUBSCRIPTION {
        int id PK
        int company_id FK
        int subscription_plan_id FK
        int payment_method_id FK
        string status
    }
    PAYMENTMETHOD {
        int id PK
        int company_id FK
        string used_for
        boolean is_default
    }
    COMPANYSTRIPEACCOUNT {
        int id PK
        int company_id FK
        string stripe_id
    }
    LEADTRANSACTIONLOG {
        int id PK
        int company_id FK
        int subscription_id FK
        int invoice_id FK
        int credits
    }
    ORDER {
        int id PK
        string order_type
        string status
    }
    ORDERITEM {
        int id PK
        int order_id FK
        string item_type
    }
```

</details>

### Shows / events & booths

`Shows` is the event, scoped by `City`, `ShowClass`, and `PriceTier` (all many-to-one, Cascade). A Show offers products through `ShowProduct` — the junction of a Show and a `Product` with show-specific quantity and pricing (composite unique `show_id, product_id`). ShowProduct is what gets added to carts and orders and what inventory counts against.

`Product` is the reusable master backing booths, workshop pavilions, sponsorships, and add-ons, typed via the self-referential `ProductType` hierarchy (Restrict throughout). Pricing has two models: **flat** (`ProductPriceTier` = Product × PriceTier) and **booth-size-based** (`ProductBoothSizePrice` = add-on Product × booth-size Product × PriceTier, and at show level `BoothSizeBasedShowProductPrices`). A Product may reference an `Agreement` (SetNull) for terms required before purchase.

`UniversalBooth` is a separate, show-agnostic booth catalog (for discovery) with its own ordered `UniversalBoothSecondaryImage` gallery (Cascade) — distinct from Product booth records. `Attendee` joins shows via `AttendeeShow` (composite unique `attendee_id, show_id`).

![Shows / events & booths](diagrams/04-shows-events-booths.svg)

<details>
<summary>Mermaid source</summary>

```mermaid
erDiagram
    CITY ||--o{ SHOWS : "hosts"
    SHOWCLASS ||--o{ SHOWS : "classifies"
    PRICETIER ||--o{ SHOWS : "prices"
    SHOWS ||--o{ SHOWPRODUCT : "offers"
    SHOWS ||--o{ ATTENDEESHOW : "registers"
    PRODUCT ||--o{ SHOWPRODUCT : "sold as"
    PRODUCT ||--o{ PRODUCTPRICETIER : "flat priced"
    PRODUCT ||--o{ PRODUCTBOOTHSIZEPRICE : "addon matrix"
    PRODUCTTYPE ||--o{ PRODUCT : "types"
    PRODUCTTYPE ||--o{ PRODUCTTYPE : "parent of"
    PRICETIER ||--o{ PRODUCTPRICETIER : "tier in"
    PRICETIER ||--o{ PRODUCTBOOTHSIZEPRICE : "tier in"
    SHOWPRODUCT ||--o{ BOOTHSIZEBASEDSHOWPRODUCTPRICES : "sized prices"
    PRODUCT ||--o{ BOOTHSIZEBASEDSHOWPRODUCTPRICES : "booth key"
    AGREEMENT ||--o{ PRODUCT : "terms for"
    UNIVERSALBOOTH ||--o{ UNIVERSALBOOTHSECONDARYIMAGE : "gallery"
    ATTENDEE ||--o{ ATTENDEESHOW : "joins"
    SHOWS {
        int id PK
        string title
        int city_id FK
        int class_id FK
        int price_tier_id FK
        string status
    }
    SHOWPRODUCT {
        int id PK
        int show_id FK
        int product_id FK
        string price_type
        int quantity
        decimal sales_price
    }
    PRODUCT {
        int id PK
        string name
        int product_type_id FK
        int agreement_id FK
        string price_type
    }
    PRODUCTTYPE {
        int id PK
        string name
        int parent_type_id FK
    }
    PRODUCTPRICETIER {
        int id PK
        int product_id FK
        int price_tier_id FK
        decimal sales_price
    }
    PRODUCTBOOTHSIZEPRICE {
        int id PK
        int product_id FK
        int booth_size_id FK
        int price_tier_id FK
    }
    BOOTHSIZEBASEDSHOWPRODUCTPRICES {
        int id PK
        int booth_id FK
        int show_product_id FK
        decimal sales_price
    }
    PRICETIER {
        int id PK
        string name
        string status
    }
    SHOWCLASS {
        int id PK
        string title
    }
    CITY {
        int id PK
        string name
        string slug
    }
    UNIVERSALBOOTH {
        int id PK
        string name
    }
    UNIVERSALBOOTHSECONDARYIMAGE {
        int id PK
        int universal_booth_id FK
        int display_order
    }
    ATTENDEESHOW {
        int id PK
        int attendee_id FK
        int show_id FK
    }
    ATTENDEE {
        int id PK
        string email
    }
    AGREEMENT {
        int id PK
        string type
    }
```

</details>

### Agreements, coupons & discounts

`Agreement` holds versioned legal templates (`ppl_terms_of_use`, `booth_terms_of_use`). Products reference an Agreement; when terms change a new Agreement row is inserted and the old soft-deleted, so historical `OrderAgreement` signatures keep their original `terms_version`. `OrderAgreement` is the per-order, immutable signature record (one-to-one with Order, Cascade).

`CouponCode` is the promo master (percentage, fixed, free product, BOGO, free leads, bundle, booth fee waiver), soft-deleted and scoped through three include/exclude junctions — `CouponProducts`, `CouponCities`, `CouponShows` (all Cascade). It optionally references a `reward_product_id` (SetNull) and `created_by` User (SetNull), and is applied to `Cart`s (SetNull). `CouponAuditLog` is an immutable ledger of every coupon mutation/redemption, many-to-one to CouponCode (Cascade), Order (SetNull, the redemption order), and the performing User (Cascade).

![Agreements, coupons & discounts](diagrams/05-agreements-coupons.svg)

<details>
<summary>Mermaid source</summary>

```mermaid
erDiagram
    AGREEMENT ||--o{ PRODUCT : "required by"
    ORDER ||--|| ORDERAGREEMENT : "signed via"
    COUPONCODE ||--o{ COUPONPRODUCTS : "scopes products"
    COUPONCODE ||--o{ COUPONCITIES : "scopes cities"
    COUPONCODE ||--o{ COUPONSHOWS : "scopes shows"
    COUPONCODE ||--o{ COUPONAUDITLOG : "audited by"
    COUPONCODE ||--o{ CART : "applied to"
    COUPONCODE }o--o| PRODUCT : "rewards"
    COUPONCODE }o--o| USER : "created by"
    COUPONPRODUCTS }o--|| PRODUCT : "targets"
    COUPONCITIES }o--|| CITY : "targets"
    COUPONSHOWS }o--|| SHOWS : "targets"
    COUPONAUDITLOG }o--o| ORDER : "redeemed on"
    COUPONAUDITLOG }o--|| USER : "performed by"
    AGREEMENT {
        int id PK
        string type
        string version
        boolean is_active
        boolean is_default
    }
    ORDERAGREEMENT {
        int id PK
        int order_id FK
        string signer_first_name
        string terms_version
        datetime signed_at
    }
    COUPONCODE {
        int id PK
        string code
        string coupon_type
        decimal discount_value
        int reward_product_id FK
        int created_by FK
        string status
    }
    COUPONPRODUCTS {
        int id PK
        int coupon_id FK
        int product_id FK
        string type
    }
    COUPONCITIES {
        int id PK
        int coupon_id FK
        int city_id FK
        string type
    }
    COUPONSHOWS {
        int id PK
        int coupon_id FK
        int show_id FK
        string type
    }
    COUPONAUDITLOG {
        int id PK
        int coupon_id FK
        int order_id FK
        int performed_by FK
        string action
    }
    ORDER {
        int id PK
        string order_number
    }
    PRODUCT {
        int id PK
        string name
    }
    CART {
        int id PK
        int coupon_code_id FK
    }
    CITY {
        int id PK
        string name
    }
    SHOWS {
        int id PK
        string title
    }
    USER {
        int id PK
        string email
    }
```

</details>

### Supporting actors & parties

`Company` is the root commercial entity and cascades to orders, subscriptions, invoices, payments, payment methods, carts, leads, gift certificates, and PPL account history. `Exhibitor` is the one-per-company login actor (unique `company_id`, Cascade). `User` is admin/sales staff — referenced as order sales rep (Restrict), cart sales rep (SetNull), coupon creator (SetNull), and across audit logs.

PPL matching uses `Attendee` (classified by `Industry`, segmented by `Category` via `CompanyCategory`/`CompanyIndustry` junctions). A matched attendee becomes a `Lead` (Company + Attendee, Cascade; CompanySubscription snapshot SetNull). `GiftCertificate` templates (Restrict) are bought as `GiftCertificatePurchase` instances (Company Cascade) and applied to orders via `GiftCertificateRedeem` (Order Restrict — can't delete an order with a redemption against it). `PPLCompanyAccountHistory` is an append-only audit of account events linking Company (Cascade) to the relevant Order, User, Subscription, Plan, and Invoice (all SetNull).

![Supporting actors & parties](diagrams/06-supporting-actors.svg)

<details>
<summary>Mermaid source</summary>

```mermaid
erDiagram
    COMPANY ||--o| EXHIBITOR : "login actor"
    COMPANY ||--o{ LEAD : "receives"
    COMPANY ||--o{ COMPANYINDUSTRY : "serves industries"
    COMPANY ||--o{ COMPANYCATEGORY : "offers categories"
    COMPANY ||--o{ COMPANYZIPCODE : "service area"
    COMPANY ||--o{ GIFTCERTIFICATEPURCHASE : "buys"
    COMPANY ||--o{ GIFTCERTIFICATEREDEEM : "redeems"
    COMPANY ||--o{ PPLCOMPANYACCOUNTHISTORY : "audited by"
    ATTENDEE ||--o{ LEAD : "becomes"
    ATTENDEE }o--|| INDUSTRY : "classified by"
    INDUSTRY ||--o{ COMPANYINDUSTRY : "mapped via"
    CATEGORY ||--o{ COMPANYCATEGORY : "mapped via"
    USER ||--o{ PPLCOMPANYACCOUNTHISTORY : "acts in"
    GIFTCERTIFICATE ||--o{ GIFTCERTIFICATEPURCHASE : "template for"
    GIFTCERTIFICATE ||--o{ GIFTCERTIFICATEREDEEM : "template for"
    GIFTCERTIFICATEPURCHASE ||--o{ GIFTCERTIFICATEREDEEM : "drawn from"
    ORDER ||--o{ GIFTCERTIFICATEREDEEM : "applied to"
    ORDER ||--o{ PPLCOMPANYACCOUNTHISTORY : "triggers"
    COMPANY {
        int id PK
        string name
        decimal lead_balance
        string status
    }
    EXHIBITOR {
        int id PK
        string email
        int company_id FK
    }
    USER {
        int id PK
        string email
        string status
    }
    ATTENDEE {
        int id PK
        string email
        int industry_id FK
    }
    LEAD {
        int id PK
        int company_id FK
        int attendee_id FK
        int company_subscription_id FK
        string status
        decimal cost
    }
    INDUSTRY {
        int id PK
        string name
    }
    CATEGORY {
        int id PK
        string name
    }
    COMPANYINDUSTRY {
        int id PK
        int company_id FK
        int industry_id FK
    }
    COMPANYCATEGORY {
        int id PK
        int company_id FK
        int category_id FK
    }
    COMPANYZIPCODE {
        int id PK
        int company_id FK
        string zip_code
    }
    GIFTCERTIFICATE {
        int id PK
        string name
        decimal amount
    }
    GIFTCERTIFICATEPURCHASE {
        int id PK
        int company_id FK
        int gift_certificate_id FK
        decimal remaining_amount
    }
    GIFTCERTIFICATEREDEEM {
        int id PK
        int order_id FK
        int company_id FK
        int gift_certificate_purchase_id FK
        decimal amount
    }
    PPLCOMPANYACCOUNTHISTORY {
        int id PK
        int company_id FK
        int order_id FK
        int user_id FK
        string event
    }
    ORDER {
        int id PK
        string order_number
    }
```

</details>

## How to regenerate

The `.mmd` files in `diagrams/` are the editable Mermaid sources. To re-render after editing (requires Node + a Chrome/Chromium install):

```bash
npx @mermaid-js/mermaid-cli -i diagrams/00-overview.mmd -o diagrams/00-overview.svg -b white
# repeat per file, or loop over diagrams/*.mmd
```

On macOS, point Puppeteer at the system Chrome with a config file (`{"executablePath": "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}`) passed via `-p`.

---

*Generated from the Prisma schema; reflects the model graph as of the current `main` branch.*
