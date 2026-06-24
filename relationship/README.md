# Entity Relationships — SBE Platform

A guide to how **orders, shows (events), payments, booths, and agreements** relate — built to help a newcomer form a **working mental model**, not to be an exhaustive reference. Derived from the authoritative Prisma schema (`admin-backend-api/prisma/schema.prisma`, the source of truth across all five services).

## How this is organised (read in this order)

It's deliberately layered so you never have to hold more than a few things in your head at once. Start at the top and go down only as far as you need.

| Level | What it is | Open this |
|---|---|---|
| **0 — Orient** | One-line definitions + a "business word → real table" map | **[glossary.md](glossary.md)** |
| **1 — Connect** | One worked example (a company buys a booth) that threads every entity together | **[the story](1-the-story/a-company-buys-a-booth.md)** |
| **2 — Zoom in** | One short card + one focused diagram per entity — *this is the core* | **[entity cards](2-entities/)** |
| **2½ — Columns** | Per-entity **schema view**: a typed ER diagram + a full data dictionary (linked 📋 from each card) | **[2-entities/schema/](2-entities/schema/)** |
| **3 — See it all** | The full, dense reference diagrams (for when you already know the pieces) | **[diagrams/](diagrams/)** |

> **New here? Do this:** skim the [glossary](glossary.md) (2 min) → read [the story](1-the-story/a-company-buys-a-booth.md) (5 min) → open the [Order](2-entities/order.md) and [Company](2-entities/company.md) cards. That's enough to navigate the codebase.

## Why it's built this way (the research)

The earlier version of this folder was a set of big, dense ER diagrams (still here, at Level 3). They were accurate but hard to *learn* from, because each one asked you to track 7–12 entities and 10–20 relationships *simultaneously*. The redesign follows three well-established ideas:

- **Cognitive Load Theory** — working memory holds only ~4 interacting elements at once; a diagram past that overloads rather than teaches. So every Level-2 diagram shows **one entity and ≤7 direct neighbors**, with attributes moved into prose.
- **Ego-network diagrams** — center one entity ("ego"), draw only its 1-hop neighbors, and omit neighbor-to-neighbor edges. Each diagram is a single digestible neighborhood; the links *between* neighbors live in *their* cards.
- **Progressive disclosure (C4-style)** — start broad, zoom in on demand. The levels above are exactly that: glossary → story → per-entity → *columns on demand* → full map.

Plus a **worked example** (Level 1): one concrete scenario narrated end-to-end is far stickier than a static schema dump.

And when you *do* need the columns, the **schema view** (Level 2½) pairs a focused, typed ER diagram with a **data dictionary** (every column: type, key, nullability, plain-English meaning) — the most-recommended human-readable schema device. It lives behind a 📋 link on each card so the card stays about the *mental model*, not the column list. Each schema view links back to the authoritative `schema.prisma` line.

## The 22 entity cards

Headline entities (the ones you asked about) **in bold**; the rest are their direct neighbors, included so nothing in a diagram is left unexplained.

- **Actors:** [Company](2-entities/company.md) · [Company Micropage](2-entities/company-micropage.md) *(the company's public CMS page)* · [Exhibitor](2-entities/exhibitor.md)
- **Catalog & event:** [Shows](2-entities/shows.md) *(the event)* · [ProductType](2-entities/product-type.md) · [Product](2-entities/product.md) *(booth/pavilion/sponsorship/add-on)* · [ShowProduct](2-entities/show-product.md) · [UniversalBooth](2-entities/universal-booth.md)
- **Company × Show:** [OnsiteBoothContact](2-entities/onsite-booth-contact.md) *(who staffs a company's booth at a given show)*
- **Buying:** [Cart](2-entities/cart.md) · [CartItem](2-entities/cart-item.md) · [CouponCode](2-entities/coupon-code.md)
- **The deal:** **[Order](2-entities/order.md)** · [OrderItem](2-entities/order-item.md) · [OrderAgreement](2-entities/order-agreement.md) · [Agreement](2-entities/agreement.md)
- **Money:** [Invoice](2-entities/invoice.md) · [PaymentTransaction](2-entities/payment-transaction.md) · [PaymentMethod](2-entities/payment-method.md)
- **PPL & extras:** [CompanySubscription](2-entities/company-subscription.md) · [PplAddonPackage](2-entities/ppl-addon-package.md) · [GiftCertificate](2-entities/gift-certificate.md)

## Three things that trip everyone up

1. **Booth, Pavilion, Sponsorship, Add-on are all one `Product` table** — separated only by `ProductType`. There are no separate "booth" or "sponsorship" tables.
2. **A Product isn't sellable until it's a `ShowProduct`** — the per-show offering with price and stock. That's what carts and orders reference.
3. **`UniversalBooth` is *not* part of ordering** — it's a standalone marketing/discovery catalog with a photo gallery, wired to nothing in the commerce flow.
4. **The "Company Micropage" is *not* one table** — it's CMS columns on `Company` plus two child tables (`CompanyService`, `CompanyTestimonialVideo`). And the `OnsiteBoothContact` (the booth staffer at a show) is a separate row keyed by company × show — don't confuse it with the company's own contact columns.

## Regenerating the diagrams

The editable Mermaid sources sit beside their renders (`2-entities/ego/*.mmd` for the card ego diagrams, `2-entities/schema/*.mmd` for the schema views, `diagrams/*.mmd` for the full maps). To re-render (needs Node + a Chrome/Chromium install):

```bash
# with @mermaid-js/mermaid-cli installed; pptr.json points Puppeteer at system Chrome:
#   {"executablePath": "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
mmdc -i 2-entities/ego/order.mmd -o 2-entities/ego/order.svg -b white -p pptr.json
mmdc -i 2-entities/schema/order.mmd -o 2-entities/schema/order.svg -b white -p pptr.json
# loop over 2-entities/ego/*.mmd and 2-entities/schema/*.mmd to rebuild all of them
```

---

*Level 2 is the heart of this guide. The dense [Level-3 diagrams](diagrams/) remain for reference, but if you're learning the model, stay in the cards.*
