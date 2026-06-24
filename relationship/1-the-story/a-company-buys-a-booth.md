# Level 1 — The story: a company buys a booth

This is the backbone of the whole model. Follow one purchase from start to finish; every entity is introduced **the moment it first matters**. Each bold name links to its own card if you want to zoom in. Don't memorise — just watch the flow.

## The cast (the "actors")

A **[Company](../2-entities/company.md)** is an exhibitor business. Someone from that company signs in through its **[Exhibitor](../2-entities/exhibitor.md)** account (one login per company). The Company is the root: every cart, order, invoice, and payment in this story ultimately belongs to it.

## 1. Browsing what's for sale

The company wants a booth at an upcoming **[Shows](../2-entities/shows.md)** — a trade-show *event* on a date, at a venue.

The booth itself lives in the catalog as a **[Product](../2-entities/product.md)**. Here is the first thing that trips people up: a "booth", a "pavilion", a "sponsorship", and an "add-on" are **all just Products** — the only difference is their **[ProductType](../2-entities/product-type.md)**.

A Product on its own isn't purchasable. It becomes buyable only when it's attached to a specific show as a **[ShowProduct](../2-entities/show-product.md)** — that's the booth *at this show*, with this show's price and stock count. (A Product may also carry a **DynamicForm** questionnaire via `dynamic_question_form_id`, to collect booth-specific answers from the buyer.)

> *(Separately, there's a **[UniversalBooth](../2-entities/universal-booth.md)** catalog — pretty marketing listings with photo galleries. It helps people browse booth styles but is **not** connected to ordering. Don't confuse it with Product.)*

## 2. Building the cart

A sales rep (or the exhibitor) builds a **[Cart](../2-entities/cart.md)** for the company — a working proposal. Each thing they add is a **[CartItem](../2-entities/cart-item.md)**: the booth is one line, and any add-ons sit *underneath* the booth line (a parent/child nesting). Each CartItem points back to the **ShowProduct** it came from.

They apply a **[CouponCode](../2-entities/coupon-code.md)** for a discount. The coupon can be limited to certain shows, products, or cities — and when applied, its discount is mirrored onto the cart's totals (this is what "discount" and "total savings" actually are: numbers on the cart/order, not tables).

## 3. Signing → the cart becomes an order

When the customer signs, the Cart converts into exactly **one** **[Order](../2-entities/order.md)**. (Enforced literally: `orders.cart_id` is unique — one cart, one order.) The Order is the heart of everything that follows.

At signature, three things happen together:

- The signature is captured as an **[OrderAgreement](../2-entities/order-agreement.md)** — an *immutable* record of who signed, when, their IP, and which terms version. Those terms came from an **[Agreement](../2-entities/agreement.md)** template that the Product required.
- Each cart line is frozen into an **[OrderItem](../2-entities/order-item.md)** — a price/quantity snapshot, so later catalog changes never rewrite history.
- Stock is drawn down: an inventory reservation ties the order to the ShowProduct's available count.

With the booth booked, onboarding asks the exhibitor for an on-site point of contact for that show — captured as an **OnsiteBoothContact** (name, email, phone), exactly one per company + show.

## 4. Billing and getting paid

The Order is billed through one or more **[Invoice](../2-entities/invoice.md)** documents and charged through one or more **[PaymentTransaction](../2-entities/payment-transaction.md)** rows — **one** for a full payment, or **N** for split installments. The card used is a saved **[PaymentMethod](../2-entities/payment-method.md)**. Once the payments add up to the total, the order is paid in full.

The company can also apply a **[GiftCertificate](../2-entities/gift-certificate.md)** toward the order.

## The other path: subscriptions & lead top-ups

Not every order comes from a cart. The platform also sells a Pay-Per-Lead program:

- A **[CompanySubscription](../2-entities/company-subscription.md)** is the company's live plan; its renewal charges create **Orders** directly (no cart, `cart_id` is null).
- A **[PplAddonPackage](../2-entities/ppl-addon-package.md)** is a one-off bundle of lead credits, also bought through an Order line.

So an **Order** has two origins: **product orders** (born from a signed Cart) and **subscription / ppl_addon orders** (born from the PPL side). The `order_type` field and whether `cart_id` is set tell them apart.

## The whole story in one breath

> A **Company** (via its **Exhibitor**) browses a **Show**, where a **Product** is offered as a **ShowProduct**. A rep builds a **Cart** of **CartItems**, applies a **CouponCode**, and the customer signs — turning the cart into one **Order** with an immutable **OrderAgreement**, frozen **OrderItems**, and reserved stock. The order is billed by **Invoices** and paid by **PaymentTransactions** on a **PaymentMethod**. Renewals of a **CompanySubscription** and **PplAddonPackage** purchases make orders the other way.

---

**Next:** open the [entity cards](../2-entities/) — start with [Order](../2-entities/order.md) (the hub) or [Company](../2-entities/company.md) (the root).
