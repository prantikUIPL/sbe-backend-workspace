# PaymentMethod

## What it is
A **saved Stripe card** for a [Company](company.md) (brand, last4, the `pm_xxx` and `cus_xxx` Stripe ids). Used to charge orders and to bill subscriptions off-session.

## Its neighborhood
![PaymentMethod ego diagram](ego/payment-method.svg)

## Relationships, read as sentences
- A PaymentMethod **belongs to** one **[Company](company.md)** (N→1, cascade).
- A PaymentMethod **is used to bill** many **[CompanySubscriptions](company-subscription.md)** (1→N, `SetNull` on the subscription side — deleting a card nulls the link, doesn't delete the subscription).

## Why it matters / gotchas
- `used_for` (`Order` vs `PPL`) marks what a stored card is intended for.
- `stripe_payment_method_id` is unique. The actual installment charges snapshot the `pm_xxx` / `cus_xxx` onto each [PaymentTransaction](payment-transaction.md) so the cron can re-charge off-session even if the card record later changes.

## Next
[Company](company.md) · [CompanySubscription](company-subscription.md) · [PaymentTransaction](payment-transaction.md)
