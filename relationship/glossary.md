# Level 0 — Glossary & term map

The 30-second orientation. Read this first; it tells you which words are real tables and which are just business language for something else.

## (a) One sentence per entity

| Entity (table) | In one sentence |
|---|---|
| **Company** | The exhibitor business that buys everything — the root that almost every commercial record hangs off. |
| **Exhibitor** | The login account for a Company (one per company); the person who signs in and checks out. |
| **Shows** | A trade-show *event* — a dated venue where booths and add-ons are sold. ("Show" = event.) |
| **ProductType** | The category tree that says whether a Product is a Booth, Workshop Pavilion, Sponsorship, or Add-on. |
| **Product** | The reusable catalog item (a booth, pavilion, sponsorship, or add-on) — *what* can be sold, before it is tied to a show. |
| **ShowProduct** | A Product offered *at a specific Show*, with that show's price and stock. The thing you actually add to a cart. |
| **UniversalBooth** | A show-agnostic marketing/discovery booth listing with a photo gallery — **not** wired into orders or pricing. |
| **Cart** | A mutable proposal/contract a sales rep builds for a Company; on signature it becomes exactly one Order. |
| **CartItem** | One line on a Cart (a booth, an add-on under that booth, or a fee). |
| **Order** | A confirmed purchase — the transactional core that gets agreed, invoiced, and paid. |
| **OrderItem** | A frozen price/quantity line on an Order (snapshot taken at purchase). |
| **OrderAgreement** | The immutable signature + terms-acceptance record for one Order (legal evidence). |
| **Agreement** | A versioned legal-terms *template* a Product can require before purchase. |
| **CouponCode** | A promo/discount that can be scoped to shows, products, or cities and applied to a Cart. |
| **Invoice** | The billing document for an Order (synced to Stripe + QuickBooks). |
| **PaymentTransaction** | One charge attempt/installment against an Order via Stripe. |
| **PaymentMethod** | A saved Stripe card for a Company. |
| **CompanySubscription** | A Company's live Pay-Per-Lead (PPL) subscription to a plan. |
| **PplAddonPackage** | A buyable lead-credit top-up package (bought through an Order line). |
| **GiftCertificate** | A gift-certificate template; *purchases* and *redemptions* of it are separate records. |

## (b) Business term → schema mapping

The single biggest source of newcomer confusion: a business word that is **not** its own table.

| You hear / say… | In the schema it actually is… |
|---|---|
| **Booth**, **Pavilion**, **Sponsorship** | A `Product` row, told apart only by its `ProductType` — **not** separate tables. |
| **Add-on** | A `Product` with an add-on `ProductType` (booth add-on); the **lead** top-up kind is `PplAddonPackage`. |
| **Discount** | The `DiscountType` enum (percentage / fixed) applied through a `CouponCode`; the dollar amount lands on `Order.coupon_amount`. |
| **Total savings** | A column, not a table — `Order.total_savings` (and `Cart.total_savings`). |
| **Booth details** | Fields on `Product` (dimensions, fees) + size pricing in `ProductBoothSizePrice` / `BoothSizeBasedShowProductPrices` + photos in `UniversalBoothSecondaryImage`. |
| **Transactions** | `PaymentTransaction`. |
| **Booth setup / cleaning fees** | Toggles on `Product`; snapshot amounts frozen onto `Order.setup_fees` / `cleaning_fees`. |

### The one idea to remember first

> **Booth, Workshop Pavilion, Sponsorship, and Booth-Add-on are all the same `Product` table — separated only by `ProductType`.** A `Product` becomes purchasable when it is attached to a `Shows` as a `ShowProduct`.

---

**Next:** read [the story](1-the-story/a-company-buys-a-booth.md) to see these pieces connect, then dive into individual [entity cards](2-entities/).
