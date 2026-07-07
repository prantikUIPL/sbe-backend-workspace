# 5. Getting the *time* right and the *person* right

← prev: [Doing it exactly once](04_DOING_IT_EXACTLY_ONCE.md) · next: [SMS and loose ends](06_SMS_AND_LOOSE_ENDS.md)

Two hard problems live here: **when** exactly to send (time zones), and **who** exactly to send to (recipients). Between them sit two HIGH findings — **S6** and **D1**.

---

# Part A — Time zones and daylight saving

🎓 **For the newcomer.**
"Send at 9 AM" sounds simple until you ask *9 AM where?* A customer in New York and one in Los Angeles have different 9 AMs. Worse, twice a year the clocks jump an hour (daylight saving), so "9 AM every day" must *stay* 9 AM across that jump. Get this wrong and reminders arrive at 8 AM or 10 AM, or — during the clock-change hour — at a time that technically doesn't exist.

🛠️ **For the engineer.** (plan §4.3) `fire_at` is built as a **local wall-clock datetime interpreted in an IANA zone** via `date-fns-tz` (`zonedTimeToUtc`), stored as UTC — never by adding fixed UTC offsets. Spring-forward gap → normalize forward; fall-back ambiguous hour → pick the earlier instant deterministically. `timezone='EVENT'` resolves from the anchor's zone with a fallback chain; RECURRING requires an explicit IANA zone.

> **📘 THE PLAN** — DST-correct wall-clock, spring-forward handled, fall-back picks the earlier instant.

> **🔎 THE REVIEW** — **approved** as current best practice. Two small asks:

### S5 (Low) — test the clock-change hour, don't just handle it
🎓 The plan *handles* the tricky clock-change hour, but the test list only checks the spring gap. Add a test for the autumn "fall-back" hour too, so the "pick the earlier one" choice is pinned and can't silently regress.
🛠️ Add an explicit unit test for the ambiguous fall-back case, not just the spring-forward gap (review S5).

### 🟠 S6 (Medium) — a bad time zone silently sends at the wrong hour
🎓 **For the newcomer.** Event time zones are typed in as free text. If someone types a **malformed** zone, the plan quietly falls back to New York time and sends anyway — with only a log warning. So a reminder fires *an hour or more off*, and nobody notices. That's exactly the "looks fine, wrong by an hour" bug that all the DST care was meant to prevent.
🛠️ `Shows.timezone` is free-form `VARCHAR(50)`; on invalid IANA the plan defaults to `America/New_York` with a warning.

> **📘 THE PLAN** — invalid event zone → default to system zone + log a warning, then send.

> **🔎 THE REVIEW — `[S6 · Medium]`.** **Validate/normalize the zone to a canonical IANA value at write/ingest time**, rejecting or flagging bad input there. At send time, if the zone is still invalid, **fail closed** (skip the occurrence + alert) rather than guessing — *a not-sent, surfaced reminder is safer than a wrong-time one.* Keep the default only for the explicitly-chosen (non-event) path.

---

# Part B — Who gets the message

🎓 **For the newcomer.**
Sometimes the address is written **plainly on the record** — the cart row has the customer's email right there. Easy. But sometimes the recipient is described **indirectly**: "the salesperson assigned to this account," "all the customer's contacts." Those have to be *looked up*, and the answer can **change over time** (salespeople get reassigned). Deciding those recipients is a whole separate feature called **DRR** (Dynamic Recipient Resolution), and it's **deferred** — so the scheduler ships by only handling the easy, written-on-the-record case.

🛠️ **For the engineer.** (plan §4 item 3, §4.7) ANCHOR_RELATIVE resolves recipients from a **column on the anchor row** (`recipient_source`) or a single documented relation hop, via a restricted allow-list (no expression DSL, no eval). Token recipients (`{salesperson}`) are **DRR (#3), deferred** — such occurrences `SKIP` with reason "recipient requires DRR." FOLLOW_UP snapshots recipients from the live send site. This is the boundary that lets the engine ship without DRR.

---

## 🔴 D1 (HIGH) — fresh recipients vs. a frozen snapshot: make it a switch

🎓 **For the newcomer.**
Here's the genuine clash. Story 77.9 says: **"resolve recipients at send time, using the most current data."** But the scheduler, to work without DRR, **photocopies the recipient list when it writes the letter** and mails to that copy. For a reminder scheduled days ahead, those differ: if a salesperson is reassigned *after* the photocopy, the *old* salesperson still gets the email.

The review's insight: **this isn't an architecture conflict — it's a product setting.** Mature senders expose it as a per-campaign switch: "determine recipients at send time — on/off." And crucially, sending in the *recipient's local time zone* is **incompatible** with send-time resolution and forces the snapshot approach anyway — which is exactly our situation.

🛠️ **For the engineer.** This is the DRR-13 resolve-timing item you carried in the gap analysis (snapshot-at-materialize-and-replay vs. most-current-at-send).

> **📘 THE PLAN** (and story 77.9 gap) — carried this as a **blocking conflict** (DRR-13): the two documents want opposite timing.

> **🔎 THE REVIEW — `[D1 · HIGH]`.** Resolve it as a **per-rule toggle**, not one global decision:
> - **Default = snapshot at materialize** (what the scheduler already does; matches time-zone-accurate sends). *No redesign — the scheduler already implements the default.*
> - **Optional `resolve_at_send` boolean** for rules that need freshness; when set, the occurrence stores a *reference* (anchor id + token spec) instead of a resolved snapshot, and DRR resolves at dispatch. Document that this path is unavailable until DRR ships and is mutually exclusive with the pre-materialized snapshot.
>
> This converts DRR-13 from a blocking conflict into a **documented product option**, and lets the BA answer "both, selectable" instead of choosing one behaviour for everyone.

**This is the review's most valuable move:** your single hardest open question becomes a one-line switch with a sensible default you've already built.

---

## D2 (Medium) — a schema mismatch that can bite beyond DRR

🎓 One customer record is marked "one exhibitor per company" in the code's schema, but the **real database allows many**. Any query that trusts "just one" can silently fetch one where there are several. It's not only a DRR problem — it can quietly break unrelated queries first.
🛠️ `Exhibitor.company_id` is `@unique` in `schema.prisma` but non-unique in the real DB index; multi-member is real.

> **🔎 THE REVIEW — `[D2 · Medium]`.** Formally **drop `@unique` from both schema files** as a standalone data-integrity fix, **decoupled from DRR timing**, so it can't bite an unrelated fetch-one query first.

---

## D3 (Medium) — never silently send to *nobody*

🎓 If, at send time, the recipient list comes back **empty**, what do you do? For a marketing reminder, quietly skipping is fine. But for a **transactional** email (order confirmation, refund), silently skipping means a customer-critical message just *vanishes* with only a log line.
🛠️ DRR gap item 6 leaves the zero-recipient fallback "subject to R&D" (skip/default/abort).

> **🔎 THE REVIEW — `[D3 · Medium]`.** Land the policy as: **skip-and-log for marketing/reminder triggers; abort-and-surface (alert) for transactional triggers; never send to zero recipients.** Tie the "surface" to the same alerting added in S3.

---

## Summary of this file's review findings

| ID | Severity | One line |
|---|---|---|
| S5 | Low | Add a unit test for the DST fall-back (ambiguous) hour, not just the gap |
| **S6** | **Medium** | Invalid event time zone silently sends at the wrong hour — validate at ingest, fail closed at send |
| **D1** | **HIGH** | Resolve-timing conflict → make it a **per-rule toggle**, default = snapshot (no redesign) |
| D2 | Medium | `Exhibitor.company_id @unique` drift — drop it now, independent of DRR |
| D3 | Medium | Zero-recipient fallback must abort-and-alert for transactional sends, never silently skip |
