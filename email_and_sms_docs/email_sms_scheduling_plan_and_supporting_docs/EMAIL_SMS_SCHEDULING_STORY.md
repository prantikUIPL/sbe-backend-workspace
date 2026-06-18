# Email & SMS Scheduling — Refined User Story (Dynamic Scheduling)

**Module:** Email & SMS Management → Scheduling
**Supersedes:** the Scheduling stories numbered `76.6` (Predefined) / `77.8` (Custom) in the Updated Epic, carried into `Email & SMS Management V2.xlsx` at file rows 7 and 20 (un-numbered there). Those remain on disk as the historical baseline.
**Date:** 2026-06-16 · **Revised:** 2026-06-18 — sync to the implementation plan, the client list, the integration guide, and the SCH register: corrected the anchor set to real model names + nullability/strength (`Shows`, not `Show`), made `frequency` optional for `FOLLOW_UP`, qualified stop-condition maturity (only `NONE` live today), added the two deferred recurring-annual Internal rows, sharpened the SMS / token deferral to materialize-then-skip altitude, and refreshed the secondary-source / provenance labels. The scheduling *model* (three kinds, timezone, stop-conditions) is unchanged. **Also folded in the `SBE_client_feedback_email_sms.pdf` thread:** the documented client driver for time-based sends (§1.1) and the caveat that several reminders the client cited land on deferred anchors (§6 / SCH-7).
**Audience:** Product / BA / Sprint planning
**Primary source material:** `ONLY_Auto_Email_Notification_Triggers.xlsx` — the client's actual email/SMS template list (the authoritative statement of *how* the client expects scheduling to behave).
**Secondary sources:** `Email & SMS Management V2.xlsx` (story text), `EMAIL_SMS_STORY_REVISIONS_V2.md` (two-epic model), `EMAIL_SMS_KNOWN_ISSUES.md` (#1 scheduling deferral, #2 SMS provider, #3 dynamic recipients), `EMAIL_SMS_SCHEDULING_KNOWN_ISSUES.md` (SCH-1..SCH-7 — scheduling-specific register), `SBE_client_feedback_email_sms.pdf` (client thread, May 14–20 2026 — the documented business driver for time-based sends; see §1).
**Companion documents:** `EMAIL_SMS_SCHEDULING_IMPLEMENTATION_PLAN.md` (the build plan) and `EMAIL_SMS_TEMPLATE_INTEGRATION_GUIDE.md` (the per-field value reference a dev uses to register a non-seeded template + its schedule).

> **Filename note:** the source workbook is `ONLY_Auto_Email_Notification_Triggers.xlsx`. All cell references below are to its `Auto Emails` sheet unless stated otherwise.

---

## 1. Why this refinement exists

The existing scheduling stories (Updated-Epic `76.6` / `77.8`, carried into V2) describe **one** capability only:

> *"As an Admin, I want to configure follow-up email schedules … so that follow-up emails are sent automatically at the defined frequency and number of days after the trigger event."*

That is a single schedule shape — **"N days after a trigger, at a frequency."** The client's real template list needs considerably more, and — critically — needs it to be **dynamic**: the admin must be able to **edit the times and offsets and have the change take effect in the running system** (no code change, no redeploy). The current story neither names the other schedule shapes the client describes, nor states the dynamic-edit requirement, nor mentions timezones — all of which appear explicitly in the client list.

This document re-derives the scheduling requirement **from the client list** and expresses it as one coherent, dynamic model.

### 1.1 The documented business driver (client feedback thread)

Time-based sending is not a UIPL-invented enhancement — it is a **standing client requirement that was never accepted as deferrable in writing.** In the `SBE_client_feedback_email_sms.pdf` thread (May 14–20 2026), UIPL proposed deferring time-delays ("we recommend proceeding with … immediate email execution for the current phase"). The client (Theo Giovanopoulos, SVP Ops) **pushed back, and his message is the last in the thread — left unanswered:**

> *"This is something that needs to be built — for example the workshop confirmation triggers 24 hours before the workshop time, the workshop keynote reminder triggers 7 days before the time of the event, electric order reminders trigger 35 and 7 days before the event, etc. So many of our trigger events are time-delay based, so if this is not built now how would you handle these triggers that were documented in our initial requirements?"* — Theo, May 20 2026

So the deferral recorded elsewhere as a *verbal* BA agreement (2026-06-03) is in tension with the client's *written* position; this dynamic-scheduling effort is the response to that demand. The thread also independently corroborates the client-list cues below — same offsets (−24h, −7d, −35d), same anchors (workshop time, event date).

### What the client actually asked for (verbatim cues from the list)

| Client cue (from the template list) | What it implies |
|---|---|
| *"Auto sends at 10AM: 30 days before event, 7 days before event, 1 days before event"* (Vendor logistics: D&L, ELITeXPO) | **Multiple offsets** before an **event-date anchor**, at a fixed **time-of-day** |
| *"Auto sends at 10AM: 30 / 7 / 3 days before event"* (Venue Manager, GSC) | Same shape, different offsets |
| *"Auto sends at 10AM: 35 days before event, 7 days before"* (Electric Orders) | Same shape, two offsets |
| *"Auto sends day before event at 8AM EST"* / *"day of event at 8AM EST"* (Event Alert) / *"day after event at 9AM EST"* (Event Photos) | Offset of −1 / 0 / +1 day around the event anchor, with an explicit **timezone** |
| *"Triggered IF scheduled by conference team 7 days before the scheduled time"* (Workshop/Keynote Reminder) | Offset of −7 days from a **workshop scheduled-time anchor** |
| *"Triggered 24 hours before workshop"* (Workshop Confirmation SMS) | −24h from the workshop anchor (SMS channel) |
| *"We will send 1 reminder every Monday and Thursday at 11AM … until [the questions are answered]"* (Unanswered product questions) | **Recurring** weekly schedule with a **stop-condition** |
| *"Triggered if contract remains unsigned after defined delay"* (Contract Reminder) | **Follow-up after trigger**, with a stop-condition (until signed) |
| *"Triggered before cart expires"* (Cart Expiration Reminder) | Offset before a **cart-expiry anchor** |
| *"Based on deadline date input when creating booth build contract"* (PPL emails) | Offset relative to an admin-entered **deadline-date anchor** |
| **NOTE 47:** *"All time based emails can be chosen based on proximity to event and times can be chosen in time zone of event or time zone of our choosing"* | **Timezone selection** per schedule: event timezone, or an explicitly chosen one |
| **NOTE 46:** *"We should be able to edit TO, CC, BCC fields at any time"* + general WYSIWYG editing | The whole configuration — including timing — is **admin-editable at any time** |

The throughline: **proximity-to-an-anchor scheduling, multi-offset, with a selectable time-of-day and timezone, fully editable, and in some cases recurring-until-resolved.**

---

## 2. The refined scheduling model

A template may have **zero or more schedule rules** — but only if the template is **marked schedulable**, and only on a trigger event the catalog marks as schedulable (the gate is described in AC-20; transactional templates such as password-reset or receipts can never carry a schedule). Each rule is one of **three kinds**. All fields on every kind are **admin-editable**, and edits apply to **future** sends only (already-sent occurrences are never rewritten).

### Kind 1 — `ANCHOR_RELATIVE` (proximity to a date)
Sends relative to a **date that lives on a domain record** (the "anchor").

- **Anchor** — which record + which date field (e.g. *PaymentTransaction.due_date* (NOT NULL, strongest), *Cart.expiration_date* (nullable), *Order.paid_in_full_at* (nullable, completion-set — set only *after* the event it marks, so it is **FOLLOW_UP-like**: only `after` offsets make sense and forward `before` offsets are rejected; see plan §4.7), *Shows.date* (date-only, weak — model is `Shows`, not `Show`), or an admin-entered *deadline date*).
- **Offsets** — one **or many** offsets, each `{ value, unit (days|hours), direction (before|after) }`. Multi-offset is first-class: *"30 / 7 / 1 days before"* is **one rule with three offsets**, not three rules.
- **Send time-of-day** — e.g. `10:00`, `08:00`, `09:00`.
- **Timezone** — `EVENT` (resolve to the anchor record's timezone, e.g. the show's) **or** an explicit IANA zone of the admin's choosing (NOTE 47). DST-correct.
- **Enabled** — on/off.

Covers: vendor/venue/GSC/electric logistics reminders, event-alert (day before / day of / day after), workshop reminder (−7d), workshop SMS (−24h), cart-expiration reminder, PPL deadline reminders, payment-due reminders.

### Kind 2 — `RECURRING` (calendar cadence)
Sends on a repeating calendar cadence until a stop-condition or end-window is reached.

- **Recurrence** — days-of-week + time-of-day (e.g. *Mon & Thu at 11:00*), or a simple interval.
- **Timezone** — same rules as above.
- **Stop-condition** *(optional)* — a domain state that ends the series (e.g. *until the product questions are answered*).
- **End window** *(optional)* — a hard stop date, independent of the stop-condition.
- **Enabled** — on/off.

Covers: unanswered-product-question reminders (*every Mon & Thu at 11AM until answered*).

### Kind 3 — `FOLLOW_UP` (after a trigger event)
This is the shape the **original story** described — retained and made precise.

- **Delay** — N days (≥ 0) after the trigger event fires.
- **Frequency / repeat** *(frequency optional)* — repeat count (number of follow-ups) is required; frequency is optional and defaults to repeating every `delayDays`. A series of offsets is allowed.
- **Send time-of-day** + **Timezone** — as above.
- **Stop-condition** *(optional)* — e.g. *until the contract is signed*; *until the cart converts*.
- **Enabled** — on/off.

Covers: contract reminder (*if unsigned after a defined delay*), and any future "remind X days after the event happened" requirement.

---

## 3. Acceptance criteria

### 3.1 Dynamic configuration (the headline requirement)
- **AC-1** An Admin can **add, edit, enable/disable, and remove** schedule rules on a template from the Template Edit screen.
- **AC-2** Editable fields per rule include: anchor (where applicable), offset(s), recurrence, send time-of-day, timezone, stop-condition, and enabled flag.
- **AC-3** Saving a schedule change **persists** it and the change **takes effect on the next worker scheduling cycle without a redeploy** (the running system reflects the new timing). This is the explicit "dynamic, not fixed" requirement.
- **AC-4** **Already-sent** occurrences are **never** retroactively changed by a later edit; only future occurrences reflect the new configuration. (Carried from V2 "Schedule Modification".)
- **AC-5** The Template **Detail View** displays the full schedule configuration read-only (time-based rules + follow-up settings). (Carried from V2.)

### 3.2 Timezone (NOTE 47)
- **AC-6** Each rule's timezone is selectable as **`EVENT`** (resolved from the anchor record) **or** an explicit IANA zone.
- **AC-7** Send instants are computed **DST-correctly** in the selected timezone (e.g. `08:00 America/New_York` is the correct UTC instant on both sides of a DST boundary).

### 3.3 Multi-offset (`ANCHOR_RELATIVE`)
- **AC-8** A single rule may carry multiple offsets; each produces its own send occurrence (e.g. one rule → sends at −30d, −7d, −1d).
- **AC-9** Each offset value is a whole number ≥ 0; `unit ∈ {days, hours}`; `direction ∈ {before, after}`. Negative or non-integer values are rejected. (Extends V2 "Days After Trigger Event".)

### 3.4 Recurring + stop-conditions
- **AC-10** A `RECURRING` rule sends on its cadence (e.g. Mon & Thu at 11:00 in the selected timezone) until its stop-condition resolves or its end-window passes.
- **AC-11** A `FOLLOW_UP` or `RECURRING` rule with a stop-condition **cancels its remaining occurrences** as soon as the bound domain state resolves (e.g. contract signed, question answered, cart converted). No further sends fire after resolution.
- **AC-12** Supported stop-conditions are an enumerated, code-controlled set (admins **select** a stop-condition, they do not author arbitrary logic). The enumerated stop-conditions are delivered incrementally as their worker resolvers land — only `NONE` is guaranteed live today; `CONTRACT_SIGNED` / `QUESTION_ANSWERED` / `CART_CONVERTED` are resolver-pending and must be bounded by a `repeatCount` or end-window until their resolver ships (cross-ref `EMAIL_SMS_SCHEDULING_KNOWN_ISSUES.md` SCH-4).

### 3.5 Predefined vs custom (two-tier model)
- **AC-13** Predefined-template schedules are editable within the **two-tier edit matrix**; **recipients (TO/FROM/sender_id) remain system-controlled and read-only** (consistent with `EMAIL_SMS_STORY_REVISIONS_V2.md` and Known-Issue #3).
- **AC-14** Custom-email-template schedules are fully editable (custom is Email-only).

### 3.6 Channel (SMS)
- **AC-15** SMS templates may **store** a schedule configuration now (the client list includes scheduled SMS — workshop confirmation −24h, product-question SMS).
- **AC-16** SMS **execution remains gated** until an SMS provider is integrated (Known-Issue #2). Email schedules execute; SMS schedules are configured, stored, and **materialized into occurrences**, but SKIPPED at dispatch (no send attempted) until the provider exists. This is a **send-time gate only — zero additional schema or story change** to turn on later.

### 3.7 Validation & audit
- **AC-17** Access control: scheduling is editable only by Admin users with the appropriate permission (mirror the existing notification-template permission guard).
- **AC-18** For `FOLLOW_UP`, delay (days ≥ 0) and repeat count are required; `frequency` is optional (when omitted the series re-fires every `delayDays`). For `RECURRING`, a recurrence cadence is required. For `ANCHOR_RELATIVE`, at least one offset is required.
- **AC-19** Every schedule create/modify/remove is written to `admin_audit_logs` with admin identity, template/rule identifier, previous and new values, and timestamp; audit entries are permanent and non-editable. (Carried from V2 "Audit".)

### 3.8 Schedulability gating (NEW — aligns the story with the build)
- **AC-20** A schedule rule may be attached **only** to a template explicitly **marked schedulable**, and a template may be marked schedulable **only** when its trigger event is marked schedulable in the **code-controlled trigger catalog** (a per-trigger ceiling). The Template Edit screen exposes the "add schedule" affordance only for such templates; non-schedulable / transactional templates (password reset, receipts, instant confirmations) can never carry a schedule. **None of the currently-seeded predefined templates are schedulable at launch** — they are all transactional/event-driven — so the first schedulable templates are newly-authored ones (per the integration guide).
- **AC-21** A scheduled email **dispatches** in this build only when its recipients are resolvable **without** dynamic token resolution — i.e. the recipient is a fixed/known address or a **column on the anchor record** (e.g. the cart or order owner's email). Sends whose recipients are tokens that require resolution (`{salesperson}`, `{all speaker email addresses}`) are **configured-and-stored but not dispatched** until DRR (Known-Issue #3) lands — a deferral gate analogous to the SMS one (AC-16): SMS occurrences skip at dispatch, token-recipient occurrences skip at materialize; both turn on with zero additional schema or story change.

---

## 4. Source-mapping table (client list → model)

Every **time-based** row in the client list **whose anchor exists or is in build scope**, mapped to a schedule kind, an anchor, and its offsets/time/timezone. The annual Employee-Birthday / Work-Anniversary recurring intents are listed below but deferred — no employee birthdate/hire-date anchor is modelled today. Rows whose anchor or template is **not yet built** are marked **[dep]** (dependency — see §6); they validate the model but are out of this effort's build scope.

| Client template (list row) | Kind | Anchor | Offsets | Time | Timezone | Channel | Notes |
|---|---|---|---|---|---|---|---|
| Vendor — D&L / ELITeXPO Logistics Reminder | `ANCHOR_RELATIVE` | Event/Show date **[dep]** | −30d, −7d, −1d | 10:00 | EVENT | Email | 3 offsets, one rule |
| Vendor — Venue Manager Reminder | `ANCHOR_RELATIVE` | Event/Show date **[dep]** | −30d, −7d, −3d | 10:00 | EVENT | Email | |
| Vendor — GSC Reminder | `ANCHOR_RELATIVE` | Event/Show date **[dep]** | −30d, −7d, −3d | 10:00 | EVENT | Email | |
| Vendor — Electric Orders Reminder | `ANCHOR_RELATIVE` | Event/Show date **[dep]** | −35d, −7d | 10:00 | EVENT | Email | |
| Internal — Event Alert (setup day) | `ANCHOR_RELATIVE` | Event/Show date **[dep]** | −1d | 08:00 | America/New_York | Email | |
| Internal — Event Alert (event day) | `ANCHOR_RELATIVE` | Event/Show date **[dep]** | 0d | 08:00 | America/New_York | Email | |
| Internal — Event Photos | `ANCHOR_RELATIVE` | Event/Show date **[dep]** | +1d | 09:00 | America/New_York | Email | |
| Product — Workshop/Keynote Reminder | `ANCHOR_RELATIVE` | Workshop scheduled time **[dep]** | −7d | (of scheduled time) | EVENT | Email | |
| Product — Workshop Confirmation SMS | `ANCHOR_RELATIVE` | Workshop scheduled time **[dep]** | −24h | — | EVENT | SMS (gated) | |
| Product — Unanswered product questions | `RECURRING` | — | Mon & Thu | 11:00 | (chosen) | Email + SMS | **Stop:** until answered |
| Store — Contract Reminder | `FOLLOW_UP` | Contract sent | "defined delay" | (chosen) | (chosen) | Email | **Stop:** until signed |
| Store — Cart Expiration Reminder | `ANCHOR_RELATIVE` | `Cart.expiration_date` ✅ | before expiry | (chosen) | (chosen) | Email | anchor exists |
| Store — Payment Due | `ANCHOR_RELATIVE` | `PaymentTransaction.due_date` ✅ | on/around due | (chosen) | (chosen) | Email | anchor exists |
| PPL — deadline reminders | `ANCHOR_RELATIVE` | Booth-build deadline date **[dep]** | per deadline | (chosen) | (chosen) | Email | "approached separately" per list |
| Internal — Employee Birthday | `RECURRING` | — (employee birthdate field) **[dep]** | annual | (chosen) | (chosen) | Email | **[dep]** no birthdate anchor modelled today |
| Internal — Employee Work Anniversary | `RECURRING` | — (employee hire-date field) **[dep]** | annual | (chosen) | (chosen) | Email | **[dep]** no hire-date anchor modelled today |

✅ = anchor already exists in the schema today (in build scope). **[dep]** = anchor/template not yet built (out of scope here; see §6).

**Recipient feasibility (per AC-21):** the two ✅ rows — Cart Expiration and Payment Due — resolve their recipient from a **column on the anchor record** (the cart/order owner), so they **send end-to-end in this build**. Rows whose recipients are tokens needing dynamic resolution (vendor/internal distribution lists, `{all speaker email addresses}`) stay deferred to DRR (#3) **even after** their anchor is built. And because **none of the 18 currently-seeded templates are flagged schedulable**, every schedulable row above is a template authored fresh per `EMAIL_SMS_TEMPLATE_INTEGRATION_GUIDE.md` (or a future custom template on a schedulable trigger), not an existing seeded one.

---

## 5. Predefined vs custom, and the existing CRUD

Scheduling plugs into the **already-built** notification-template CRUD (Listing / Search / Filter / Detail / Edit). It does **not** introduce a separate screen — per V2, it lives **within Template Edit** and is shown read-only in **Template Detail View**. The two-tier rules (predefined = system-seeded, recipients read-only; custom = Email-only, full edit) are unchanged; scheduling simply adds an editable schedule section governed by the same matrix.

---

## 6. Out of scope / dependencies (record, don't own)

- **Unbuilt client templates + their anchors** — the vendor/venue/GSC/electric logistics emails, the event-alert / event-photos internal emails, and the workshop confirm/reminder product emails are **not among the currently-built predefined triggers**, and their primary anchor (the **event/show date + timezone**, the **workshop scheduled time**) is not yet wired as a schedulable anchor. These are flagged as dependencies; the build effort targets the anchors that exist today (`Cart.expiration_date`, `PaymentTransaction.due_date`, `Order.paid_in_full_at`, and the show date/timezone **where already modelled**). Bringing the full client catalog in is a separate, larger effort.

  > **Coverage caveat (from the client feedback thread, §1.1).** The time-based reminders the client cited in the thread — workshop confirmation (−24h on **workshop time**), workshop keynote reminder (−7d on **event time**), electric order reminders (−35d & −7d on **event date**) — **all anchor on the event / workshop / show-date anchors that this build defers.** The in-scope anchors (`Cart.expiration_date`, `PaymentTransaction.due_date`, `Order.paid_in_full_at`) carry the cart-expiry, payment-due, and order-follow-up cases, but **none of the event-proximity reminders the client cited.** This effort delivers the scheduling *engine*; those event-proximity use-cases remain non-functional until the event/workshop/show-date anchors (and their timezones) are modelled. Tracked as **SCH-7** in `EMAIL_SMS_SCHEDULING_KNOWN_ISSUES.md`.
- **SMS provider** (Known-Issue #2) — scheduled SMS is modelled and stored now; occurrences materialize but dispatch is SKIPPED until a provider is integrated.
- **Dynamic recipient resolution** (Known-Issue #3) — resolving tokens like `{salesperson}`, `{all speaker email addresses}` at send time is a separate deferred story. Scheduled sends whose recipients are **fixed or a column on the anchor record** (cart/order owner email) do **not** need it and dispatch now; only **token-recipient** sends are gated on DRR (per AC-21).
- **"Other relevant system emails" source list** (Known-Issue #4) — no observed source endpoint; owner TBD.

---

## 7. Known-issues impact

- **#1 Scheduling** — moves from *"deferred / documentation-only"* to **in design** (this document + the implementation plan).
- **#2 SMS provider** — unchanged; scheduled SMS execution depends on it.
- **#3 Dynamic recipient resolution** — unchanged; a prerequisite for some scheduled sends to reach the right recipients.
- **#21 Predefined-vs-custom shadowing at send time** — to be fixed **as part of** the scheduling build (already agreed to ship "together with the scheduling logic").
