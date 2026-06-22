# Shows (the event)

## What it is
A **trade-show event** — a dated thing at a venue, in a city. This is the "event" entity (there is no separate `Event` table; **Shows is it**). A show carries a lot of logistical venue detail, but relationally its job is simple: it's the place where Products are sold.

## Its neighborhood
![Shows ego diagram](ego/shows.svg)

## Relationships, read as sentences
- A Show **is held in** a **City**, **classified as** a **ShowClass**, and **priced by** a **PriceTier** (each N→1, cascade).
- A Show **offers products as** many **[ShowProducts](show-product.md)** (1→N) — this is how a catalog Product becomes purchasable at this show.
- A Show **is attended via** many **AttendeeShow** join rows (1→N).
- A Show **is scoped by coupons via** many **CouponShows** rows (1→N) — i.e. a [CouponCode](coupon-code.md) can include/exclude this show.

## Why it matters / gotchas
- A Product is **never** sold "at a show" directly — it always goes through **[ShowProduct](show-product.md)**, which holds the show-specific price, stock and visibility.
- `(city_id, title)` is unique — you can't have two identically-titled shows in the same city.
- Lots of `venue_*` / `gsc_*` columns are pure logistics text; they have no relational meaning.

## Next
[ShowProduct](show-product.md) · [Product](product.md) · [CouponCode](coupon-code.md)
