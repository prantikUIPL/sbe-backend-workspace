# 6. SMS — no longer parked — and the loose ends

← prev: [Time and who](05_TIME_AND_WHO.md) · next: [The review scorecard](07_THE_REVIEW_SCORECARD.md)

Holds the review's third HIGH finding — **M1**, a five-minute doc fix — plus the SMS story and the small cross-document tidy-ups.

**New since 2026-07-08:** this file's framing changed more than any other in the guide. When the plan and review were written, SMS was deliberately deferred; it now **ships** in the combined release alongside scheduling (76.6/77.8) and DRR (77.9). The 📘/🔎 content below is preserved history (any factual correction is disclosed in italics — never silent); each finding now carries a third box — **📦 WHERE IT LANDED** — recording where it became concrete spec. (Background: [the combined release](08_THE_COMBINED_RELEASE.md).)

---

## Why SMS was deliberately parked — and why it now ships

🎓 **For the newcomer.**
Text messages (SMS) are on the roadmap but **not built yet**. The design is careful to let email scheduling ship *without waiting for SMS*: when a planned send is a text, the mailroom **materializes it but then marks it "skipped — SMS not integrated"** and never tries to send. So SMS is fenced off cleanly rather than half-done. *(That framing has since changed — see the 📦 box below.)*

🛠️ **For the engineer.** (plan §4 item 10) A denormalized `occurrence.channel` column makes the boundary a query: dispatch filters `channel='EMAIL'`; a separate pass flips `channel='SMS'` PENDING rows to `SKIPPED` "SMS provider not integrated." There are 0 SMS templates today regardless.

> **🔎 THE REVIEW** — the materialize-then-SKIP gate is in Section 4's "explicitly right, keep as-is." The SMS *gap analysis* was called "genuinely strong." But four things about SMS still need attention:

> **📦 WHERE IT LANDED — (combined-release docs, 2026-07-08)** — SMS is no longer parked: story 76.8 ships in this combined release, so the mailroom is getting its texting desk after all — and the "skipped — SMS not integrated" stamp stays on that desk only until un-gate day. Mechanism: **Twilio Programmable Messaging** — the client said "SendGrid," but SendGrid's API is email-only, so Twilio is the feasible same-vendor-family mechanism, held as question **SMS-01** for written client confirmation (confirmed, never assumed). The day-one critical path is external: **A2P 10DLC brand + campaign registration** (days-to-weeks; carriers block 100% of unregistered traffic since Feb 2025) starts the moment SMS-01 is confirmed — the [integration spine](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_INTEGRATION_SPINE.md) calls it the release long pole (milestone MS0). The SKIP gate itself was the right design and survives as the **interim boundary** until spine milestone MS9, where it lifts in two deliberately separate flips (spine §1.3 rows 2 and 4): the **H1 code flip** — remove the SKIP pass, widen the dispatch select, extend the by-id channel assertion with a `channel==='SMS'` → `SmsService` branch — may deploy **dark** once the SMS story's §9 checklist steps 1–6 are green in order (occurrences then log `SKIPPED "sms sending disabled by config"` — observable, harmless); the **launch toggle** — `ppl_settings` key `sms_sending_enabled`, default `'false'` — flips only when 10DLC is registered, the number/Messaging Service is provisioned, and the consent decision (SMS-03) is recorded. That last flip is a settings edit plus cache invalidate, no deploy — which also makes it the fastest rollback lever. Spec: [SMS implementation plan](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_76.8_SMS_IMPLEMENTATION_PLAN.md) (Step H1, Rollout steps 3–4).

---

## 🔴 M1 (HIGH) — correct a status note before the client sees it

🎓 **For the newcomer.**
A separate status document (our "known issues" register) currently says SMS storage/editing is **"already built, zero schema change."** But the code actually **blocks** creating an SMS template today. If a client or project manager reads that note, they'll think SMS is nearly done when it isn't. This is a **five-minute text edit with outsized credibility impact** — fix the wording so it doesn't overstate readiness.

🛠️ **For the engineer.**
`EMAIL_SMS_KNOWN_ISSUES.md` (#2, #12) states SMS storage/edit is "already built, zero schema change," but code hard-blocks SMS create (`SUPPORTED_TEMPLATE_CHANNELS=['EMAIL']`, service throws), seeds zero SMS rows, and left the SMS `channel_config` shape read-only-but-undefined. The gap analysis already caught this.

> **📘 THE PLAN / register** — says SMS storage is "already built, zero schema change."

> **🔎 THE REVIEW — `[M1 · HIGH]` — do immediately.** Correct the known-issues text to read **"SMS create is gated; storage shape undefined."** Otherwise the register overstates readiness. *"A five-minute doc edit with outsized credibility impact."*

> **📦 WHERE IT LANDED — (combined-release docs, 2026-07-08)** — The five-minute fix is now a formal, tracked to-do with an owner — and it grew from one edit to three. M1 is an entry in the [open-questions register](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_OPEN_QUESTIONS.md) (section H "Process & release", Tier 4, owner: **the user** — both register files are frozen to this doc pipeline, so every register edit is a user action), with **three tracked sub-items**: **(a)** the original wording fix — `EMAIL_SMS_KNOWN_ISSUES.md` #2/#12 corrected to "SMS create is gated; storage shape undefined"; **(b)** the **SCH-3** note to the scheduling register — snapshot PII is bounded by the S1 retention window, and its staleness half is answered by D1's per-rule `resolve_at_send` toggle (see [file 4](04_DOING_IT_EXACTLY_ONCE.md), S7); **(c)** the **SCH-4** note — the planned stop-condition resolver list shrinks after the X1 `CART_CONVERTED` drop (below). The [integration spine](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_INTEGRATION_SPINE.md)'s release-gate checklist (gate E) requires all three applied **before any client-facing review**.

> ⚠️ **Note on scope:** editing `EMAIL_SMS_KNOWN_ISSUES.md` touches the **main** (non-scheduling) known-issues register. Per your standing rule to keep scheduling and main registers separate, treat this as a deliberate, isolated correction to the main register — not a scheduling-doc change. (The register entry preserves this: all three sub-items are user-applied precisely because the register files stay frozen to the pipeline.)

---

## M2 (Medium) — 2026 SMS compliance is under-specified

🎓 **For the newcomer.**
Texting people in the US has strict legal rules, and they got stricter. You must register your business with the carriers, honour "STOP" and other opt-outs, keep consent records for years, and **not text during quiet night hours** — and those hours now **vary by state**. The plan's single "8 AM–9 PM" window isn't enough for a national audience. When the review was written this was pre-scoping for a deferred SMS; now that SMS ships in the combined release, this list stopped being "for later" and became build spec.

🛠️ **For the engineer.** (review M2, sharpens SMS gap items 3 & 8)
- **State-aware quiet hours** (e.g. FL/OK/WA effectively 8 AM–8 PM; Texas 9 AM–9 PM Mon–Sat, noon–9 PM Sun). A flat window is insufficient.
- **Opt-out via "any reasonable method,"** not only the carrier-handled STOP keyword → a **platform-controlled suppression store** is needed regardless of provider.
- **Consent retained ≥ 5 years.**
- **Hard gate:** since Feb 2025 carriers **block 100%** of unregistered 10DLC traffic. Add a pre-launch checklist item: **no SMS in production until the 10DLC brand + campaign are registered and the sending number/messaging service is provisioned.**

> **📦 WHERE IT LANDED — (combined-release docs, 2026-07-08)** — Every bullet became a built thing: the texting desk gets its own do-not-text ledger, a consent logbook that is never shredded, and a state-by-state clock. The [SMS implementation plan](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_76.8_SMS_IMPLEMENTATION_PLAN.md)'s **compliance substrate** (DD-8/DD-9, Steps D1–D2) specs it concretely: a platform-**authoritative** `sms_suppressions` table keyed by E.164 number, recording opt-outs from *any* reasonable method — provider STOP webhooks *and* manually registered requests — checked pre-send on every dispatch (suppressed ⇒ no provider call, outcome logged `suppressed`; rows are never deleted, re-opt-in sets `released_at`; Twilio's account-level STOP handling stays on as defense-in-depth only); an append-only `sms_consent_events` table with **≥5-year retention, explicitly excluded from every purge job**; and **state-aware quiet hours as `ppl_settings` data**, updatable without redeploy — `sms_quiet_hours_default` `'08:00-21:00'` (the TCPA baseline) plus a JSON overrides map (FL/OK/WA `08:00-20:00`; TX `09:00-21:00` Mon–Sat, `12:00-21:00` Sun), destination state derived from the NANP area code, and an in-window violation **defers** the occurrence to the next allowed window (stays `PENDING`, `next_attempt_at` set, `attempt_count` untouched — a deferral is not a retry) rather than dropping or sending anyway. The hard gate is verbatim in the plan as **AC-16**: no production SMS before 10DLC brand + campaign registration and Messaging Service provisioning — enforced by the default-off `sms_sending_enabled` kill switch, with registration kicked off day one (spine MS0) as the release long pole. The consent *policy* (which entity holds consent) stays open as **SMS-03** — the tables build now because they're required under every possible answer.

---

## M3 (Medium) — the logbook can't record a phone number yet

🎓 **For the newcomer.**
The send logbook has a single "email" column and no way to say "this was a text, sent to this number." Before any SMS can be sent, the logbook needs a **channel marker and a general recipient column** — one logbook for both email and SMS, not a second table.

🛠️ **For the engineer.** (review M3, SMS gap item 5) Extend `NotificationLog` with `channel` + a generalized recipient column (admin-owned migration, propagated via `db push`), rather than a separate SMS log table — one audit surface, one query path. **Prerequisite for SMS dispatch**; sequence it right after the scope decision (SMS gap item 2), not alongside send code.

> **📦 WHERE IT LANDED — (combined-release docs, 2026-07-08)** — The logbook gets exactly one upgrade, specced in exactly one place: the unified **§1.2 migration** in the [integration spine](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_INTEGRATION_SPINE.md) (`<ts>_ems_unified_notification_spine`, admin-owned, `db push`-mirrored to the other four repos). On `notification_logs` it adds `channel` (`NotificationChannel` enum, **NOT NULL DEFAULT 'EMAIL'** — the default backfills every historical row correctly, since all of them are email) plus the generalized recipient columns — **and only those**; `notification_template_id` already exists NOT NULL, so no template-link column is needed. Roles are named so it stays ONE migration: **spine §1.2 is the spec of record, the [DRR plan](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_77.9_DRR_IMPLEMENTATION_PLAN.md)'s Step 1 is the execution home, SMS Step B1 is the consumer/verifier** — neither track ships its own variant, and a second SMS-specific log migration anywhere is a release-constraint violation (halt). The review's sequencing intent holds: it lands at spine MS3, **before any SMS send code merges** (the SMS dark build, MS5, depends on it). One deliberate loosening, flagged as **SPINE-Q1** in the register: the DRR schedule wants the migration at its own Phase D1 even before SMS-02's written confirmation — safe, because the `channel` default is inert if SMS were ever stood down; M3's intent was ordering relative to *send code*, which is preserved.

---

## M4 (Low) — break the SMS↔DRR chicken-and-egg by ordering

🎓 SMS needs to resolve phone numbers; that resolution is part of DRR; DRR today is email-only; and both were deferred — a loop. Break it by deciding the **order**: build **email DRR first**, then SMS reuses that same machinery extended to a phone field, instead of building a parallel one.

🛠️ (review M4, SMS gap item 7 + DRR gap item 9) State the sequence: (1) ship email DRR generalizing the scheduler's restricted resolver; (2) SMS reuses it, extended to a phone field. Removes the circularity on paper.

> **📦 WHERE IT LANDED — (combined-release docs, 2026-07-08)** — Adopted verbatim as the [integration spine](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_INTEGRATION_SPINE.md)'s **binding build order**: email DRR first (MS6) — generalizing the scheduler's restricted resolver into the one shared `RecipientResolutionService`, with the scheduler's restricted forms as the *degenerate tier of the same engine*, not a separate code path — then the scheduler consumes it, then **SMS extends the same engine to a phone field** (SMS plan Step F1, MS8, only after DRR's AC-19 interface review freezes the phone seam). The circularity is broken on paper *and* mechanically policed: the DRR Gate Contract grep fails any PR that adds recipient parsing outside `recipient-resolution/`. This ordering is also why a DRR slip strands SMS even though DRR needs no provider — stated plainly on the spine's critical path (MS2 → MS4 → MS6 → MS8 → MS9).

---

## X1 (Low) — drop a stop-reason that isn't a distinct state yet

🎓 **For the newcomer.**
The list of "reasons to stop chasing" includes two that mean **the same thing today** — "contract signed" and "cart converted" — because on the current data a cart *becomes* an order the moment it's signed. Shipping both invites a future developer to use "cart converted" expecting different behaviour that doesn't exist. Drop it until it's genuinely different.

🛠️ **For the engineer.** (review X1) The plan itself notes `CONTRACT_SIGNED` and `CART_CONVERTED` are aliases on today's schema. **Drop `CART_CONVERTED` from the enum** until a genuinely distinct state is modelled, keeping the stop-condition set honest.

> **📦 WHERE IT LANDED — (combined-release docs, 2026-07-08)** — Adopted, cleanly: the Phase 1 migration creates the stop-condition enum as **`{ CONTRACT_SIGNED, QUESTION_ANSWERED, NONE }`** — `CART_CONVERTED` never enters the Postgres enum or any of the five `schema.prisma` mirrors, and no resolver, DTO literal, or seed references it ([Scheduling Fixes Addendum §8](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_SCHEDULING_FIXES_ADDENDUM.md)). `CONTRACT_SIGNED` (parse `'cart:ID'`, resolved when `carts.status='signed'`) covers the real use case, and re-adding later is cheap and additive (`ALTER TYPE … ADD VALUE`). No open decision — the review resolved the plan's own either/or. Slot: spine **MS2** (applied at Phase 1), with a release-gate B checklist line ("enum shipped without CART_CONVERTED"). The follow-on bookkeeping — the SCH-4 scheduling-register note that the planned resolver list shrinks (`QUESTION_ANSWERED` stays `[dep]` per S4) — is tracked as **M1 sub-item (c)** above.

---

## X2 (Low) — add three test cases to match the new fixes

🎓 The plan's test list is already thorough. Add three checks matching the fixes above so they're actually verified.
🛠️ (review X2) Add: **retention** (terminal rows older than the window are purged in batches; active untouched — S1); **reaper double-send** (a stuck SENDING row past the stale window is retried; at-least-once documented — S2); **bad time zone** (invalid zone rejected at ingest / fails closed at send — S6).

> **📦 WHERE IT LANDED — (combined-release docs, 2026-07-08)** — All three are now written down as concrete cases appended to plan §8 ([Scheduling Fixes Addendum §9](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_SCHEDULING_FIXES_ADDENDUM.md)): **(1) retention** — seed all terminal statuses stale + fresh + PENDING/SENDING; assert only stale terminal rows are deleted, in batches of `schedule_retention_batch_size`, and that the protected latest-SENT FOLLOW_UP row survives (S1's purge guard, verified); **(2) reaper double-send** — force a `SENDING` row past `schedule_sending_stale_minutes`; the pass condition is literally "the second dispatch occurs and is logged" — the at-least-once honesty test, extended to provider-boundary suppression *only if* ADD-Q1 adopts idempotency; **(3) bad timezone** — garbage tz at ingest ⇒ 400, never persisted; an EVENT rule with an invalid/null anchor tz and no `schedule.timezone` ⇒ `SKIPPED "unresolvable event timezone"` plus alert, never a defaulted-zone send. They land during Phase 3/4 (spine **MS4**, "S5/X2 tests"), and release-gate B closes on them explicitly: "X2's three verification cases green … — **tests, not prose**."

---

## Summary of this file's review findings

| ID | Severity | One line | Where it landed |
|---|---|---|---|
| **M1** | **HIGH** | Correct the "SMS already built" known-issues text before the client sees it | Register entry (section H, Tier 4, user-applied) — 3 sub-items incl. the SCH-3/SCH-4 notes; spine gate-E precondition for client review |
| M2 | Medium | 2026 SMS compliance (state-aware quiet hours, suppression store, 5-yr consent, 10DLC gate) is under-specified | SMS plan compliance substrate (DD-8/DD-9): `sms_suppressions` + append-only `sms_consent_events`, `ppl_settings` quiet-hours data, 10DLC hard gate = AC-16 + kill switch |
| M3 | Medium | `NotificationLog` needs channel + generalized recipient before any SMS dispatch | The ONE spine §1.2 migration — `channel` + recipients only (`notification_template_id` already exists); DRR Step 1 executes; lands MS3, before SMS send code |
| M4 | Low | Break the SMS↔DRR loop by sequencing email DRR first | Spine binding build order: email DRR (MS6) → scheduler consumes → SMS phone extension (MS8, post AC-19 freeze); Gate-Contract grep enforces one resolver |
| X1 | Low | Drop `CART_CONVERTED` from the enum until it's a distinct state | Addendum §8 — Phase 1 enum ships without it, all five schemas; spine MS2 + gate-B line; SCH-4 note = M1 sub-item (c) |
| X2 | Low | Add retention / double-send / bad-timezone cases to the verification list | Addendum §9 — the exact three cases appended to plan §8; gate B requires them green at MS4 ("tests, not prose") |
