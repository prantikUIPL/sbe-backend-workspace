# 5. Getting the *time* right and the *person* right

← prev: [Doing it exactly once](04_DOING_IT_EXACTLY_ONCE.md) · next: [SMS and loose ends](06_SMS_AND_LOOSE_ENDS.md)

Two hard problems live here: **when** exactly to send (time zones), and **who** exactly to send to (recipients). Between them sit two of the review's weightiest findings — **S6** and **D1** (the file's one HIGH).

**New since 2026-07-08:** every finding below now carries a third box — **📦 WHERE IT LANDED** — pointing at the combined-release doc that turned the recommendation into a concrete spec. The 📘/🔎 content is preserved history (any factual correction is disclosed in italics — never silent); the 📦 box is what happened next. (Background: [the combined release](08_THE_COMBINED_RELEASE.md).)

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

> **📦 WHERE IT LANDED — (combined-release docs, 2026-07-08)** — The missing test is now written down, letter for letter. [Addendum §5](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_SCHEDULING_FIXES_ADDENDUM.md) specs the exact case: a rule at `send_time='01:30'` in `America/New_York`, materialized for 2026-11-01 (fall-back day), must produce `fire_at = 2026-11-01T05:30:00Z` — the **earlier** instant (01:30 EDT, UTC−4), not `06:30:00Z` — and the choice must be deterministic across repeated computation (the idempotent `dedupe_key` upsert yields exactly one row). Test task only, zero behavior change; it lands with the Phase-3 DST tests (spine milestone MS4, "S5/X2 tests"), in the same PR as the materializer's wall-clock math, and the release-gate checklist counts it explicitly — "tests, not prose."

### 🟠 S6 (Medium) — a bad time zone silently sends at the wrong hour
🎓 **For the newcomer.** Event time zones are typed in as free text. If someone types a **malformed** zone, the plan quietly falls back to New York time and sends anyway — with only a log warning. So a reminder fires *an hour or more off*, and nobody notices. That's exactly the "looks fine, wrong by an hour" bug that all the DST care was meant to prevent.
🛠️ `Shows.timezone` is free-form `VARCHAR(50)`; on invalid IANA the plan defaults to `America/New_York` with a warning.

> **📘 THE PLAN** — invalid event zone → default to system zone + log a warning, then send.

> **🔎 THE REVIEW — `[S6 · Medium]`.** **Validate/normalize the zone to a canonical IANA value at write/ingest time**, rejecting or flagging bad input there. At send time, if the zone is still invalid, **fail closed** (skip the occurrence + alert) rather than guessing — *a not-sent, surfaced reminder is safer than a wrong-time one.* Keep the default only for the explicitly-chosen (non-event) path.

> **📦 WHERE IT LANDED — (combined-release docs, 2026-07-08)** — Adopted whole, and the silent guess is gone: a letter with an unreadable postmark now goes back on the shelf with a note, instead of being mailed at New York time and hoped about. [Addendum §6](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_SCHEDULING_FIXES_ADDENDUM.md) is a *fix-before-Phase-3-ships* delta with two halves. **Ingest:** `Shows.timezone` is validated to a canonical IANA value at write time in admin-backend-api (`Intl.supportedValuesOf('timeZone')` / `date-fns-tz` — the same library the worker uses, so the two ends can't disagree); invalid new writes get a 400, and legacy rows get a one-time **read-only audit** handed to the data owner, never a silent rewrite. **Send:** the EVENT chain is now `anchor.timezone` (must validate) → `schedule.timezone` (IANA, if set) → occurrence **`SKIPPED` with reason `"unresolvable event timezone"`** plus a warn/alert log — **`schedule_default_timezone` is removed from the EVENT fallback chain entirely** (it survives only as an admin-UI authoring default). Blast-radius note from the recon: the two Phase-3 anchors (`CART`, `PAYMENT_TRANSACTION`) carry no timezone column, so shipping fail-closed now costs Phase 3 nothing. Gate B of the [integration spine](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_INTEGRATION_SPINE.md) requires "S6 tz fail-closed live", and X2's third verification case pins both ends in tests.

---

# Part B — Who gets the message

🎓 **For the newcomer.**
Sometimes the address is written **plainly on the record** — the cart row has the customer's email right there. Easy. But sometimes the recipient is described **indirectly**: "the salesperson assigned to this account," "all the customer's contacts." Those have to be *looked up*, and the answer can **change over time** (salespeople get reassigned). Deciding those recipients is a whole separate feature called **DRR** (Dynamic Recipient Resolution), and when the plan was approved it was **deferred** — so the scheduler was designed to ship by only handling the easy, written-on-the-record case. (That framing has since changed — see the 📦 box below.)

🛠️ **For the engineer.** (plan §4 item 3, §4.7) ANCHOR_RELATIVE resolves recipients from a **column on the anchor row** (`recipient_source`) or a single documented relation hop, via a restricted allow-list (no expression DSL, no eval). Token recipients (`{salesperson}`) are **DRR (#3)** — deferred at plan time — and such occurrences `SKIP` with reason "recipient requires DRR." FOLLOW_UP snapshots recipients from the live send site. This is the boundary that lets the engine ship without DRR.

> **📦 WHERE IT LANDED — (combined-release docs, 2026-07-08)** — **DRR is no longer deferred.** Story 77.9 ships in the same combined release as the scheduler (scheduling 76.6/77.8 + DRR 77.9 + SMS 76.8 — see [The combined release](08_THE_COMBINED_RELEASE.md)). The plan's SKIP-with-reason boundary stays exactly as designed, but it is now the **interim** boundary, not the final one: the [DRR implementation plan](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_77.9_DRR_IMPLEMENTATION_PLAN.md) generalizes the scheduler's restricted resolver into one shared `RecipientResolutionService` (the scheduler becomes a consumer of it), and at DRR deploy the token-recipient SKIP **un-gates** ([spine](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_INTEGRATION_SPINE.md) §1.3 row 1, milestone MS6) — occurrences that used to SKIP "recipient requires DRR" simply begin resolving. In mailroom terms: the room finally hired the person who looks addresses up, and the "hold — no address clerk yet" tray empties itself.

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

> **📦 WHERE IT LANDED — (combined-release docs, 2026-07-08)** — **ADOPTED — the switch got built into the plans, exactly as the review drew it, and it is now the timing contract for the whole release.** The [DRR plan](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_77.9_DRR_IMPLEMENTATION_PLAN.md) (DD-5) specs it concretely: `notification_schedules.resolve_at_send Boolean NOT NULL DEFAULT false` — snapshot-at-materialize stays the default for every rule, existing and new; an opt-in rule stores a **reference shape** (`mode:'reference'` inside `recipients_snapshot` — anchor ref + token spec, no second column) and the dispatcher grows **exactly one branch**: toggle on → engine resolves at dispatch inside the claim; toggle off → replay the snapshot verbatim, engine never called. Config-time, `resolve_at_send=true` is rejected until DRR is deployed and is mutually exclusive with timezone-accurate/EVENT snapshot semantics — both enforced in the admin DTO validator. The [spine](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_INTEGRATION_SPINE.md) §1.1.3 elevates this to the **shared timing contract** all three tracks obey (SMS inherits it with no variance). BA sign-off is tracked in the [open-questions register](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_OPEN_QUESTIONS.md) as **D1 (/DRR-13)** — section F, Tier 0, carried as *adjudicated-pending-sign-off* with the expected answer "both, selectable"; if the BA rejects it, the branch ships dark and snapshot remains the only mode. One honest wrinkle the adoption records: under at-least-once delivery (S2), a reaper-reset re-dispatch with the toggle **on** may re-resolve to a *different* recipient set — accepted as the freshness semantics the toggle opts into, with each attempt's actual resolution audited.

---

## D2 (Medium) — a schema mismatch that can bite beyond DRR

🎓 One customer record is marked "one exhibitor per company" in the code's schema, but the **real database allows many**. Any query that trusts "just one" can silently fetch one where there are several. It's not only a DRR problem — it can quietly break unrelated queries first.
🛠️ `Exhibitor.company_id` is `@unique` in **all five** repos' `schema.prisma` (admin/exhibitor/external `:1030`, worker/pulse `:944`) but non-unique in the real DB index; multi-member is real.

> **🔎 THE REVIEW — `[D2 · Medium]`.** Formally **drop `@unique` from both schema files** as a standalone data-integrity fix, **decoupled from DRR timing**, so it can't bite an unrelated fetch-one query first. *(The review's "both schema files" reflects that its gap analysis had only examined two; the 2026-07-08 recon found the drift in all five. See the 📦 box.)*

> **📦 WHERE IT LANDED — (combined-release docs, 2026-07-08)** — Landed as [addendum §10](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_SCHEDULING_FIXES_ADDENDUM.md), and the fix turned out **bigger than the review knew: five schemas, not two.** Recon verified the `@unique` in all five repos — a sibling left uncorrected would `db push` the unique index right back — so each of the five drops `@unique` and gains `@@index([company_id])`. The admin migration is **idempotent** (verify live state first): `DROP CONSTRAINT IF EXISTS` / `DROP INDEX IF EXISTS` / `CREATE INDEX IF NOT EXISTS`, then mirror + `db push` ×4. The Company back-relation flips `exhibitor Exhibitor?` → `exhibitors Exhibitor[]`, which breaks every singular call site **at compile time — deliberately** (today's code compiles while being wrong about the data): recon sizes it at ~25 real sites, each getting an explicit one-vs-many decision, never a silent `[0]`. It runs on its **own branch/PR, never bundled into a scheduling phase** — spine milestone **MS1** ("decoupled — do soon"), with a contingency: if not landed by MS3, DRR Step 1 absorbs it. It is the hard **prerequisite for DRR's `{all customer contacts}` token** (gate B checks it), and the [register](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_OPEN_QUESTIONS.md) carries it as entry **D2** (section G, Tier 3, default: approve — rejecting makes DRR FR-8 unbuildable). And "multi-member is real" is now proven, not inferred: the invite flow deliberately creates multi-exhibitor companies (`exhibitor-backend-api/src/company_user/company_user.service.ts:237-248`).

---

## D3 (Medium) — never silently send to *nobody*

🎓 If, at send time, the recipient list comes back **empty**, what do you do? For a marketing reminder, quietly skipping is fine. But for a **transactional** email (order confirmation, refund), silently skipping means a customer-critical message just *vanishes* with only a log line.
🛠️ DRR gap item 6 leaves the zero-recipient fallback "subject to R&D" (skip/default/abort).

> **🔎 THE REVIEW — `[D3 · Medium]`.** Land the policy as: **skip-and-log for marketing/reminder triggers; abort-and-surface (alert) for transactional triggers; never send to zero recipients.** Tie the "surface" to the same alerting added in S3.

> **📦 WHERE IT LANDED — (combined-release docs, 2026-07-08)** — The "subject to R&D" gap is now a decided policy, built into the shared engine word-for-word as the review split it. The [DRR plan](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_77.9_DRR_IMPLEMENTATION_PLAN.md) (DD-6) has the engine compute a **disposition** that consumers act on: zero recipients + marketing/reminder → **SKIP** with reason `"zero recipients — skipped (marketing)"`; zero + transactional → **ABORT**, recorded failed with reason `"zero recipients — aborted (transactional)"` plus an alert raised on **the S3 alert channel the scheduling addendum establishes** — no new alert mechanism; **never send to zero** in any case. The transactional/marketing classification lives on the code-controlled trigger catalog: `trigger_events.is_transactional Boolean NOT NULL DEFAULT false`, with the seeder setting an **explicit** value for every seeded slug and a unit test that fails on any default-only row (a DB default can't be distinguished from a decision). The per-trigger classification content is a BA deliverable, tracked in the [register](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_OPEN_QUESTIONS.md) as entry **D3** (section C, Tier 2, default = the review's split); SMS inherits the whole policy unchanged.

---

## Summary of this file's review findings

| ID | Severity | One line | Where it landed |
|---|---|---|---|
| S5 | Low | Add a unit test for the DST fall-back (ambiguous) hour, not just the gap | Addendum §5 — exact fall-back case specced (`01:30` NY on 2026-11-01 ⇒ the earlier instant); ships with the Phase-3 DST tests (spine MS4, gate B) |
| **S6** | **Medium** | Invalid event time zone silently sends at the wrong hour — validate at ingest, fail closed at send | Addendum §6 — IANA validation at ingest (invalid ⇒ 400; legacy read-only audit) + send-side `SKIPPED "unresolvable event timezone"` + alert; `schedule_default_timezone` removed from the EVENT chain (MS4, before Phase 3 ships) |
| **D1** | **HIGH** | Resolve-timing conflict → make it a **per-rule toggle**, default = snapshot (no redesign) | **ADOPTED** — `resolve_at_send` column + reference mode + one dispatcher branch (DRR plan DD-5); spine §1.1.3 makes it the release-wide timing contract; BA sign-off = register D1 (/DRR-13), Tier 0 |
| D2 | Medium | `Exhibitor.company_id @unique` drift — drop it now, independent of DRR | Addendum §10 — **five-schema** fix (not two), idempotent migration + compile-time back-relation flip (~25 sites); own milestone MS1, prerequisite for `{all customer contacts}`; register D2 |
| D3 | Medium | Zero-recipient fallback must abort-and-alert for transactional sends, never silently skip | DRR plan DD-6 — skip-and-log marketing / abort-and-alert transactional via `trigger_events.is_transactional`, riding the S3 alert channel; register D3 (BA classifies triggers) |
