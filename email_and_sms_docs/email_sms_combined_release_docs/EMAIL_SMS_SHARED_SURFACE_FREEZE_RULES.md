# Shared-Surface Freeze Rules — Email & SMS Combined Release

**Audience:** every team lead and developer working on the SBE backends during the Email & SMS combined-release build (Scheduling 76.6/77.8 + Dynamic Recipients 77.9 + SMS 76.8).
**One-line summary:** we are **not** asking anyone to stop their work — we are putting cones around **four specific spots** where your work and ours touch the same code.

---

## Why this document exists

While the Email & SMS plans were being written, normal development continued — as it should. A code audit (2026-07-08) compared our plans against the latest `dev` and found that almost nothing other teams did affects us. **But four shared spots showed real collision risk**, including one that already happened: a hardcoded payment-reminder timer shipped on the exact database field our new scheduler will also watch, which means a customer could receive **the same reminder twice** unless we coordinate.

A full code freeze would be overkill — most teams work in code we never touch. These four rules are the whole ask.

---

## The four rules

### Rule 1 — Don't change the send logbook (`notification_logs`)

> 🧊 **Frozen:** any migration or schema change to the `notification_logs` table, in any repo.

**In simple terms:** every email the platform sends leaves a record in one logbook. Our release adds two columns to it (a "was this an email or a text?" marker and a general recipient field) in **one single migration**. If another team alters the same table in the same window, one of the two migrations breaks on deploy.

**If you need a change to this table:** bring it to the Email & SMS track — we will fold it into our single migration rather than racing it.

### Rule 2 — New email send code builds on top of ours, not beside it

> 🧊 **Frozen:** independent changes to the template-lookup logic inside the four mailer services
> (`admin`/`exhibitor`/`external` → `src/common/services/mailer.service.ts`, `worker` → `src/notification/mailer.service.ts`).

**In simple terms:** all email leaves the building through four mail counters. We are changing how those counters pick the letter template (fixing a known defect, #21, where a custom template can shadow a predefined one). **Adding a new email send is fine** — new templates, new triggers, business as usual. Just don't rewrite the counter's lookup logic yourself, and expect to rebase your send code once our change lands.

### Rule 3 — No new self-timed reminders (the important one)

> 🧊 **Frozen:** building any **new hardcoded cron/timer that sends reminder or follow-up emails** based on a date field (due dates, expiry dates, event dates) — without checking with the Email & SMS track first.

**In simple terms:** this release ships a general **scheduling engine** — one machine that handles all "send X days before/after Y" emails. If teams keep building their own private timers in parallel (as already happened with payment reminders on `PaymentTransaction.due_date`, and cart-expiry mails), we end up with **two machines watching the same date**, and customers get duplicate emails. From now on: a new timed email is either **built on the new engine** (once it exists) or **registered with us** so the double-send is designed out.

**One-off, event-driven emails are NOT covered by this rule** — only *time-based* ones ("N days before/after…").

### Rule 4 — Don't lean on the "one exhibitor per company" shortcut

> 🧊 **Frozen:** writing new code that uses `company.exhibitor` (singular) or otherwise assumes a company has exactly one exhibitor.

**In simple terms:** the schema currently carries a false promise — it claims each company has exactly **one** exhibitor account, but the real database allows **many** (and multi-member companies exist). Code that trusts the promise silently picks an arbitrary member. We are removing the false promise as one of our **first** milestones, and every place that leans on it must be fixed by hand. Each new usage written this week is another spot to fix next week — one new usage already appeared during the seven days we audited.

**Instead:** if you need "the exhibitor(s) of a company," query the list and state which one you mean (first? owner? all?).

---

## What is explicitly NOT frozen

- ✅ **Seeding new email templates and trigger events for your feature** — that is the standing rule (each story owns its templates) and our design expects it: new templates arrive with scheduling switched *off* and cannot break the engine.
- ✅ All work in code the release doesn't touch — which is almost everything: orders, carts, payments, gift certificates, attendees, dashboards…
- ✅ Sending one-off, event-driven emails from your features (Rule 2's rebase note is the only ask).
- ✅ Reading `notification_logs` — only *changing its shape* is frozen.

---

## How long the cones stay up

The freeze is **milestone-scoped, not calendar-scoped** — and it shrinks fast because the risky pieces are deliberately scheduled first:

| Rule | Lifts when |
|---|---|
| Rule 4 (exhibitor shortcut) | The `@unique` fix lands on dev — **first milestone (MS1)**, days not weeks |
| Rule 1 (logbook) | The single unified migration lands on dev — early milestone |
| Rule 2 (mail counters) | The by-id dispatch + #21 fix lands on dev |
| Rule 3 (self-timed reminders) | **Permanent policy change** — once the scheduling engine ships, timed emails go through it |

---

## What happens to timers that were already built

**Decision (2026-07-08): absorption.** Anything already built in the engine's territory — the payment-reminder timer from story 24.15, the cart-expiry mail, and anything similar that merges before the build starts — will be **replaced by and absorbed into the scheduling engine**, not run beside it. Their settings become schedule rules, their duplicate-protection is superseded by the engine's, and their templates (already seeded) simply get rules. A full absorption inventory will be produced by the re-audit that runs once all currently in-flight work is merged.

---

## Questions / exceptions

Talk to the Email & SMS track before merging anything you suspect touches Rules 1–4. The answer will usually be "fine, just sequence it after milestone X" — the point of this document is that the conversation happens **before** the merge, not after a customer gets two reminders.

*Companion docs: the [integration spine](EMAIL_SMS_COMBINED_RELEASE_INTEGRATION_SPINE.md) (milestone order MS0–MS9), the [open-questions register](EMAIL_SMS_COMBINED_RELEASE_OPEN_QUESTIONS.md), and the scheduling/DRR/SMS plans in this folder.*
