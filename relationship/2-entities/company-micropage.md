# Company Micropage (CMS profile)

## What it is
The Company's public **CMS "micropage"** — a marketing/profile page that exhibitors fill in for their booth. It is **not one table**: it's a mix of **scalar columns ON the [Company](company.md) row** (cover image, promo video, a single attendee offer, the medallion certificate) plus **two ordered child tables** (`CompanyService`, `CompanyTestimonialVideo`). It backs a **"Step 2 of 3"** profile-completion flow (driven by `profile_completed_at`) and exposes an **auto-generated medallion certificate** the company can show off and download.

## Its neighborhood
![Company Micropage ego diagram](ego/company-micropage.svg)

📋 **Need the columns?** → [Company Micropage schema view](schema/company-micropage.md) (typed fields + data dictionary)

## Relationships, read as sentences
- A **CompanyService** **belongs to** one **[Company](company.md)** (N→1, **cascade**) — the list of services a company offers, **ordered by `display_order`**.
- A **CompanyTestimonialVideo** **belongs to** one **[Company](company.md)** (N→1, **cascade**) — the testimonial videos shown on the page, **ordered by `display_order`**.
- The page's **scalar content** — cover/hero image, promo video, the single attendee offer (title, description, discount %, link), and the medallion certificate (number, URL, issued-at) — are **columns on Company itself**, not separate tables.

## Why it matters / gotchas
- **It is NOT one table.** Scalar fields live on Company; the repeating sections (services, testimonials) are the two child tables. Don't go looking for a `company_micropages` table.
- **Both child lists are ordered** by `display_order` (default `0`) — render in that order, not insertion order.
- **`medallion_certification_number` is `@unique` and auto-generated** — one globally-unique cert number per company; `medallion_url` is the generated image, `medallion_generated_at` is when it was issued.
- **`profile_completed_at`** drives the progress indicator ("Step 2 of 3") — it's a marker, not a boolean.
- **Exactly one attendee offer per company** — the offer is a set of scalar columns on Company, so there's no second offer.
- `cover_image` NULL ⇒ the CMS shows a default generic image (frontend fallback).

## Next
[Company](company.md) · [OnsiteBoothContact](onsite-booth-contact.md)
