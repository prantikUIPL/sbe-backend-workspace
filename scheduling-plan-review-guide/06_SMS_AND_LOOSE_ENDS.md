# 6. SMS (parked) and the loose ends

← prev: [Time and who](05_TIME_AND_WHO.md) · next: [The review scorecard](07_THE_REVIEW_SCORECARD.md)

Holds the fourth HIGH finding — **M1**, a five-minute doc fix — plus the SMS story and the small cross-document tidy-ups.

---

## Why SMS is deliberately parked

🎓 **For the newcomer.**
Text messages (SMS) are on the roadmap but **not built yet**. The design is careful to let email scheduling ship *without waiting for SMS*: when a planned send is a text, the mailroom **materializes it but then marks it "skipped — SMS not integrated"** and never tries to send. So SMS is fenced off cleanly rather than half-done.

🛠️ **For the engineer.** (plan §4 item 10) A denormalized `occurrence.channel` column makes the boundary a query: dispatch filters `channel='EMAIL'`; a separate pass flips `channel='SMS'` PENDING rows to `SKIPPED` "SMS provider not integrated." There are 0 SMS templates today regardless.

> **🔎 THE REVIEW** — the materialize-then-SKIP gate is in Section 4's "explicitly right, keep as-is." The SMS *gap analysis* was called "genuinely strong." But four things about SMS still need attention:

---

## 🔴 M1 (HIGH) — correct a status note before the client sees it

🎓 **For the newcomer.**
A separate status document (our "known issues" register) currently says SMS storage/editing is **"already built, zero schema change."** But the code actually **blocks** creating an SMS template today. If a client or project manager reads that note, they'll think SMS is nearly done when it isn't. This is a **five-minute text edit with outsized credibility impact** — fix the wording so it doesn't overstate readiness.

🛠️ **For the engineer.**
`EMAIL_SMS_KNOWN_ISSUES.md` (#2, #12) states SMS storage/edit is "already built, zero schema change," but code hard-blocks SMS create (`SUPPORTED_TEMPLATE_CHANNELS=['EMAIL']`, service throws), seeds zero SMS rows, and left the SMS `channel_config` shape read-only-but-undefined. The gap analysis already caught this.

> **📘 THE PLAN / register** — says SMS storage is "already built, zero schema change."

> **🔎 THE REVIEW — `[M1 · HIGH]` — do immediately.** Correct the known-issues text to read **"SMS create is gated; storage shape undefined."** Otherwise the register overstates readiness. *"A five-minute doc edit with outsized credibility impact."*

> ⚠️ **Note on scope:** editing `EMAIL_SMS_KNOWN_ISSUES.md` touches the **main** (non-scheduling) known-issues register. Per your standing rule to keep scheduling and main registers separate, treat this as a deliberate, isolated correction to the main register — not a scheduling-doc change.

---

## M2 (Medium) — 2026 SMS compliance is under-specified

🎓 **For the newcomer.**
Texting people in the US has strict legal rules, and they got stricter. You must register your business with the carriers, honour "STOP" and other opt-outs, keep consent records for years, and **not text during quiet night hours** — and those hours now **vary by state**. The plan's single "8 AM–9 PM" window isn't enough for a national audience. None of this changes the "SMS is deferred" decision; it just scopes the work correctly for when SMS is pulled forward.

🛠️ **For the engineer.** (review M2, sharpens SMS gap items 3 & 8)
- **State-aware quiet hours** (e.g. FL/OK/WA effectively 8 AM–8 PM; Texas 9 AM–9 PM Mon–Sat, noon–9 PM Sun). A flat window is insufficient.
- **Opt-out via "any reasonable method,"** not only the carrier-handled STOP keyword → a **platform-controlled suppression store** is needed regardless of provider.
- **Consent retained ≥ 5 years.**
- **Hard gate:** since Feb 2025 carriers **block 100%** of unregistered 10DLC traffic. Add a pre-launch checklist item: **no SMS in production until the 10DLC brand + campaign are registered and the sending number/messaging service is provisioned.**

---

## M3 (Medium) — the logbook can't record a phone number yet

🎓 **For the newcomer.**
The send logbook has a single "email" column and no way to say "this was a text, sent to this number." Before any SMS can be sent, the logbook needs a **channel marker and a general recipient column** — one logbook for both email and SMS, not a second table.

🛠️ **For the engineer.** (review M3, SMS gap item 5) Extend `NotificationLog` with `channel` + a generalized recipient column (admin-owned migration, propagated via `db push`), rather than a separate SMS log table — one audit surface, one query path. **Prerequisite for SMS dispatch**; sequence it right after the scope decision (SMS gap item 2), not alongside send code.

---

## M4 (Low) — break the SMS↔DRR chicken-and-egg by ordering

🎓 SMS needs to resolve phone numbers; that resolution is part of DRR; DRR today is email-only; and both are deferred — a loop. Break it by deciding the **order**: build **email DRR first**, then SMS reuses that same machinery extended to a phone field, instead of building a parallel one.

🛠️ (review M4, SMS gap item 7 + DRR gap item 9) State the sequence: (1) ship email DRR generalizing the scheduler's restricted resolver; (2) SMS reuses it, extended to a phone field. Removes the circularity on paper.

---

## X1 (Low) — drop a stop-reason that isn't a distinct state yet

🎓 **For the newcomer.**
The list of "reasons to stop chasing" includes two that mean **the same thing today** — "contract signed" and "cart converted" — because on the current data a cart *becomes* an order the moment it's signed. Shipping both invites a future developer to use "cart converted" expecting different behaviour that doesn't exist. Drop it until it's genuinely different.

🛠️ **For the engineer.** (review X1) The plan itself notes `CONTRACT_SIGNED` and `CART_CONVERTED` are aliases on today's schema. **Drop `CART_CONVERTED` from the enum** until a genuinely distinct state is modelled, keeping the stop-condition set honest.

---

## X2 (Low) — add three test cases to match the new fixes

🎓 The plan's test list is already thorough. Add three checks matching the fixes above so they're actually verified.
🛠️ (review X2) Add: **retention** (terminal rows older than the window are purged in batches; active untouched — S1); **reaper double-send** (a stuck SENDING row past the stale window is retried; at-least-once documented — S2); **bad time zone** (invalid zone rejected at ingest / fails closed at send — S6).

---

## Summary of this file's review findings

| ID | Severity | One line |
|---|---|---|
| **M1** | **HIGH** | Correct the "SMS already built" known-issues text before the client sees it |
| M2 | Medium | 2026 SMS compliance (state-aware quiet hours, suppression store, 5-yr consent, 10DLC gate) is under-specified |
| M3 | Medium | `NotificationLog` needs channel + generalized recipient before any SMS dispatch |
| M4 | Low | Break the SMS↔DRR loop by sequencing email DRR first |
| X1 | Low | Drop `CART_CONVERTED` from the enum until it's a distinct state |
| X2 | Low | Add retention / double-send / bad-timezone cases to the verification list |
