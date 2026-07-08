# 3. The three kinds of schedule

← prev: [The schedulable switch](02_THE_SCHEDULABLE_SWITCH.md) · next: [Doing it exactly once](04_DOING_IT_EXACTLY_ONCE.md)

---

## The three flavours

🎓 **For the newcomer.** A standing instruction comes in three shapes:

| Kind | The instruction reads like… | Everyday example |
|---|---|---|
| **ANCHOR_RELATIVE** | "send X days *before/after* a date" | "3 days before the cart expires" |
| **RECURRING** | "send on a repeating calendar" | "every Monday & Thursday at 11 AM" |
| **FOLLOW_UP** | "send a chase-up series after something happened, until it's resolved" | "every week after we send a contract, until it's signed" |

🛠️ **For the engineer.** (plan §2.1) `enum NotificationScheduleKind { ANCHOR_RELATIVE, RECURRING, FOLLOW_UP }`. A per-kind validation matrix (§2.1.1) enforces which fields are required/forbidden per kind — e.g. `offsets` required for ANCHOR_RELATIVE, forbidden for the others; `recurrence` required only for RECURRING; `timezone='EVENT'` invalid for RECURRING.

---

## Kind 1 — ANCHOR_RELATIVE ("before/after a date")

🎓 The reminder **counts from a date on a record** (the anchor). "3 days before expiry" means: find the expiry date, subtract 3 days, send then. The date can move — if the customer extends their cart, the reminder slides with it.

🛠️ Materialized via a **multi-offset look-ahead window**: select anchor rows whose date falls inside `now() ± max offset`, and for each row × each offset, upsert a PENDING occurrence with `fire_at = anchor_field ± offset` computed as DST-correct wall-clock (plan §4.3). In-scope anchors today: `Cart.expiration_date` (nullable) and `PaymentTransaction.due_date` (not-null). `Order.paid_in_full_at` is FOLLOW_UP-only; `Shows.date` is deferred (date-only, weak).

---

## Kind 2 — RECURRING ("a repeating calendar")

🎓 Fires on a **calendar cadence** — days of the week at a time, or every N days — until a hard stop (an end date, or a resolved condition like "the question was answered").

🛠️ Materialized **per-schedule** (not per-anchor) via a **bounded roll-forward**: from the last materialized instant up to `now() + horizon` (default 14 days), compute each matching instant in the rule's IANA zone and upsert PENDING. Only IANA zones are valid (no `EVENT`). A "until answered" variant binds per instance (`order_product:ID`) and rolls one occurrence at a time (plan §4.3).

> **🔎 THE REVIEW — `[S4 · Medium]`.** The **"RECURRING until answered"** case has a gap: the plan never defines the query that *discovers which instances currently need a series* (which order-products have unanswered questions), and its stop-condition (`QUESTION_ANSWERED`) depends on an answer table that **isn't modelled yet**. So that one use case has neither a start query nor a live stop resolver.
>
> **Fix:** cleanest is to **defer** the "unanswered product questions" recurring template alongside the other deferred dependencies (matching how the show/workshop anchors are already deferred). If it *must* ship, define the enumerating query and require an `end_window_at` bound until the answer table lands. Reviewer recommends deferring — "it keeps Phase 4 honest."

> **📦 WHERE IT LANDED — (combined-release docs, 2026-07-08)** — The reviewer's "defer it" option was adopted: the "nag until the question is answered" reminder does **not** ship in this release, but the machinery that would run it does. [Addendum §4](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_SCHEDULING_FIXES_ADDENDUM.md) defers the template alongside the show/workshop anchors on the plan's §9 deferred list ("engine supports it, data model does not yet"), while the per-instance RECURRING *mechanics* — per-instance `anchor_instance_ref`, one-at-a-time roll-forward, stop-on-resolve — still ship in Phase 4, exercised by tests. Hard rule while `QUESTION_ANSWERED` stays unimplemented: any rule carrying that stop-condition MUST also carry an `end_window_at` / `repeatCount` bound. The final call is **ADD-Q3** in the [open-questions register](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_OPEN_QUESTIONS.md) (Tier 2, owner: BA) — default if unanswered: defer. If the business overrides to must-ship, the answer table and the instance-discovery query must be specced in writing first.

---

## Kind 3 — FOLLOW_UP ("a chase-up series")

🎓 Something happens (a contract is sent); then you send a **series** of nudges spaced out over time, and you **stop when it's resolved** (signed) or you hit a ceiling (e.g. after 5 tries or 60 days).

🛠️ Two capture modes (plan §4 item 8): **(1) send-site capture** — piggyback on an existing live send that already knows the recipient; **(2) after-anchor** — realized as an after-dated ANCHOR_RELATIVE rule when the "after" event is a timestamp column (the in-scope *Store Contract Reminder*). The original trigger instant is frozen as `series_anchor_at` so a late send never drifts the series; each nudge is `series_anchor_at + N × interval`.

---

## The catch-up question (applies to all three)

🎓 **For the newcomer.** Suppose the mailroom was **shut for 26 hours** (an outage). When it reopens, should it send yesterday's reminders — or skip them as stale? The plan's answer: **skip anything more than 24 hours late**, for everything, uniformly.

🛠️ `schedule_dispatch_max_catchup_minutes` default 1440 (24h). Occurrences with `fire_at < now() - window` are `SKIPPED` "missed send window." RECURRING never enumerates every missed slot — it computes only the next due instant forward (plan §4 item 3).

> **📘 THE PLAN** — one global 24-hour catch-up window; older-than-that is skipped.

> **🔎 THE REVIEW — `[S3 · Medium]`.** 24 hours is right for a *proximity reminder* ("7 days before your event," sent 30 h late, is just noise). It's **not** obviously right for every kind — a **payment-due or contract reminder** that came due during a 26-hour outage arguably still should send. One global window bakes a single policy into all kinds.
>
> **Fix:** make catch-up **selectable** — a per-kind default (proximity reminders skip; payment/follow-up send anyway) or a per-rule `catchup_policy` of `SKIP`/`SEND`, with 24 h as the skip threshold. **At minimum, log/alert every occurrence the sweep skips**, so a silent mass-skip after an outage is visible, not invisible.

> **📦 WHERE IT LANDED — (combined-release docs, 2026-07-08)** — Adopted in full: when the mailroom reopens, it now checks each standing instruction's own late-mail rule — and shouts about every letter it bins. [Addendum §3](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_SCHEDULING_FIXES_ADDENDUM.md) adds a `catchup_policy` column to `notification_schedules` — enum `NotificationCatchupPolicy { SKIP, SEND }`, **NOT NULL `@default(SKIP)`** (admin migration + 4× schema mirror + `db push`). The sweep auto-SKIPs stale PENDING rows only for `SKIP` rules; `SEND` rules dispatch late through the normal path, where the stop-condition pass and live-anchor reconcile run first — so a late send against an already-resolved anchor is CANCELLED, not delivered. The 24 h `schedule_dispatch_max_catchup_minutes` default is unchanged as the skip threshold. Alerting ships too: a warn-level log line per skipped occurrence plus one aggregate line per tick ("catch-up sweep: skipped N occurrences across M schedules"). Lands at spine milestone MS4 (the column may ride the MS2 Phase-1 migration). One open decision, **ADD-Q2** in the [open-questions register](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_OPEN_QUESTIONS.md) (Tier 3, Tech Lead + BA): single default-SKIP with per-rule override, or additionally per-kind DTO defaults (proximity→SKIP, payment/follow-up→SEND) — default: the former, one explicit column and no hidden kind-based behavior.

---

## Summary of this file's review findings

| ID | Severity | One line | Where it landed |
|---|---|---|---|
| S3 | Medium | One-size 24h catch-up can drop a legitimately-due send; make it per-kind/per-rule + alert on skips | Adopted — addendum §3: per-rule `catchup_policy` enum column (NOT NULL, default `SKIP`) + per-skip and aggregate alerting; ADD-Q2 tracks the per-kind-defaults variant |
| S4 | Medium | "RECURRING until answered" has no discovery query and a not-yet-modelled stop table — defer it | Adopted (defer) — addendum §4: template deferred with the other deferred dependencies, mechanics still ship with tests; ADD-Q3 (BA, Tier 2) holds the final call |
