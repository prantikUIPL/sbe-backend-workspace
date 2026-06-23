# Exhibitor

## What it is
The **login account** for a Company — the person who signs in, browses shows, and checks out. There is exactly **one Exhibitor per Company** (the `company_id` is unique). Think "Company = the business, Exhibitor = the user who represents it."

## Its neighborhood
![Exhibitor ego diagram](ego/exhibitor.svg)

📋 **Need the columns?** → [Exhibitor schema view](schema/exhibitor.md) (typed fields + data dictionary)

## Relationships, read as sentences
- An Exhibitor **belongs to** exactly one **[Company](company.md)** (1→1, cascade).
- An Exhibitor **can invite** other Exhibitors (self-relation on `invited_by`; `SetNull` so removing the inviter doesn't delete invitees). Each invitee is a **full Exhibitor with its own unique `company_id` → its own Company** — an invite is a *peer referral between separate accounts*, not adding a teammate to the inviter's company.
- An Exhibitor **has an assigned strategist** and a **referrer** — both point to **User** (internal admin/sales staff), `SetNull`. The *strategist* is the ongoing account manager (one staff User manages many exhibitors; changes are tracked in `SalesStrategistAuditLog`); the *referrer* (`referred_by`) is the staff member credited with acquiring this exhibitor (set-once provenance).
- *Also linked to:* ExhibitorSession, ExhibitorToken, ContactMessage, NotificationLog, ExhibitorAuditLog (auth/audit internals).

## Why it matters / gotchas
- Because `company_id` is **unique**, you never have two Exhibitor logins for one Company in this model. There's no membership/seats table — "multiple users per company" simply can't be expressed today.
- **Two different "referral" concepts, same English word:** `invited_by` → **Exhibitor** (a customer invited another customer) vs `referred_by` → **User** (an internal salesperson is credited with the acquisition). Different target tables, different meanings — don't conflate them.
- The booth-buying flow is driven by the Company, not the Exhibitor — the Exhibitor is just the authenticated actor. Carts created by an exhibitor are stamped with `created_by_type = exhibitor` (a polymorphic owner, no FK).

## Next
[Company](company.md) · [Cart](cart.md)
