# Glossary — every term, defined twice

Each term gets a **🎓 plain** definition (mailroom analogy, no web knowledge assumed) and a **🛠️ technical** definition (the real thing). Skim the plain column first; drop into the technical column when you need precision.

---

### Schedule (a "rule")
- 🎓 A **standing instruction**: "mail a reminder 3 days before any cart expires." It doesn't name a person — it's the general policy.
- 🛠️ A `notification_schedules` row (plan §2.1). Columns say the *kind*, the *anchor*, the *offsets*, the *time zone*, and when to *stop*. One template can carry several.

### Occurrence (one planned send)
- 🎓 One **specific letter** the standing instruction produced: "the reminder for Jane's cart, due next Tuesday 9 AM."
- 🛠️ A `notification_schedule_occurrences` row (plan §2.2). Has a `fire_at` (when to send), a `status`, a frozen recipient list, and a unique `dedupe_key`.

### Anchor
- 🎓 The **calendar event** a reminder hangs off — the cart's expiry date, the payment's due date. The reminder is "3 days *before this*."
- 🛠️ A column on a real domain row — `Cart.expiration_date`, `PaymentTransaction.due_date`, `Order.paid_in_full_at` (plan §4 item 7). The `fire_at` is computed as anchor ± offset.

### Materialize
- 🎓 **Writing out the individual letters ahead of time** from the standing instruction, so they're ready to mail on the right day.
- 🛠️ The worker turning rules + anchors into concrete PENDING occurrence rows each tick (plan §4.3). Idempotent — running it twice makes no duplicates.

### Dispatch
- 🎓 **Dropping the letters in the mailbox** when their day arrives.
- 🛠️ Selecting occurrences that are due (`fire_at <= now()`), sending each via the mailer, and marking them `SENT` (plan §4 item 3).

### Tick / heartbeat
- 🎓 The mailroom clerk **doing a round every few minutes** — check what's due, send it, go back to waiting.
- 🛠️ A cron job in `background-worker-service` firing every `schedule_dispatch_interval_minutes` (default 5) and running one `runTick()` (plan §4 item 1).

### Dedupe key
- 🎓 A **serial number** stamped on each letter. If a letter with that serial already went out, you never mail another.
- 🛠️ A `@unique` string on the occurrence, built from *stable* parts (rule + instance + offset), **never** from `fire_at` (plan §2.2, §4.3). Guarantees one occurrence per (rule, instance, offset).

### Claim / `SENDING` status
- 🎓 A clerk **grabbing a letter and marking it "in progress"** so no other clerk grabs the same one.
- 🛠️ An atomic `updateMany WHERE status=PENDING SET status='SENDING'` — the row-level lock that stops two workers sending the same occurrence (plan §2.2, §4 item 3).

### Reaper
- 🎓 A **supervisor** who notices a letter has been "in progress" too long (the clerk went home) and puts it back in the pile.
- 🛠️ A top-of-tick sweep resetting `SENDING` rows stuck past `schedule_sending_stale_minutes` (15) back to `PENDING`, so a crash mid-send self-heals (plan §4 item 3).

### Retention / purge
- 🎓 **Shredding old delivered-letter records** so the filing cabinet doesn't overflow.
- 🛠️ A cleanup job that deletes occurrences in a terminal state (SENT/SKIPPED/etc.) after a retention window. **This is the one thing the plan was missing** — review finding **S1**. *(Landed 2026-07-08: fully specced as a daily retention cron in the fixes addendum §1 — see [file 8](08_THE_COMBINED_RELEASE.md).)*

### At-least-once vs. exactly-once
- 🎓 "At-least-once" = *we will never fail to send, but in a rare crash-and-retry you might get the same letter twice.* "Exactly-once" = *never zero, never two.* True exactly-once is very hard.
- 🛠️ The design is **at-least-once**: the reaper can re-dispatch a slow send. Review **S2** says: state this honestly and, if you want, add provider-side idempotency later. *(Landed: the addendum states it verbatim in the service doc-comment; the idempotency option is tracked as register question ADD-Q1.)*

### Time zone / DST
- 🎓 Making sure **"9 AM" means 9 AM in the recipient's city**, even across the spring/autumn clock change.
- 🛠️ Wall-clock computed in an IANA zone via `date-fns-tz`, stored as UTC (plan §4.3). `timezone='EVENT'` reads the zone off the anchor; otherwise an explicit zone is required.

### DRR — Dynamic Recipient Resolution
- 🎓 Figuring out **who the letter actually goes to** when the address isn't written plainly on the record — e.g. "the salesperson assigned to this account," which has to be looked up.
- 🛠️ Story 77.9. Resolving token recipients (`{salesperson}`, `{all customer contacts}`) via lookup. **Deferred when this guide was written — now shipping in the combined release (2026-07-08)**: the scheduler handles plain-column recipients itself (plan §4 item 3) until the shared DRR engine deploys and the token gate lifts. See [file 8](08_THE_COMBINED_RELEASE.md).

### Snapshot (recipients_snapshot)
- 🎓 **Photocopying the address list at the moment you write the letter**, then mailing to that copy — even if the real list changes later.
- 🛠️ The resolved `{to[], cc[], bcc[], replacements}` frozen onto the occurrence at materialize/capture time, replayed verbatim at dispatch (plan §2.2). The alternative — re-resolve at send — is review finding **D1**. *(Landed: adopted as the per-rule `resolve_at_send` toggle, default = this snapshot; see the new terms below.)*

### `is_schedulable` (the switch) / `supports_scheduling` (the ceiling)
- 🎓 A **light switch** on each letter template ("this one *may* be scheduled") and a **master breaker** on the event type ("events like *this* are even allowed to have scheduled letters"). The switch only works if the breaker is on.
- 🛠️ `is_schedulable` on `NotificationTemplate`; `supports_scheduling` on `TriggerEvent` (plan §2.0). A template may be schedulable only if its trigger allows it. See [`02_THE_SCHEDULABLE_SWITCH.md`](02_THE_SCHEDULABLE_SWITCH.md).

### The three kinds
- 🎓 Three flavours of standing instruction: **before/after a date** (ANCHOR_RELATIVE), **on a repeating calendar** (RECURRING), **a chase-up series** (FOLLOW_UP). See [`03_THE_THREE_KINDS.md`](03_THE_THREE_KINDS.md).
- 🛠️ Enum `NotificationScheduleKind { ANCHOR_RELATIVE, RECURRING, FOLLOW_UP }` (plan §2.1).

### Stop-condition
- 🎓 A reason to **stop chasing**: "keep reminding until the contract is signed — then stop."
- 🛠️ A code-controlled enum evaluated each tick; resolved state cancels remaining PENDING occurrences (plan §4 item 4). The plan listed `CONTRACT_SIGNED`, `QUESTION_ANSWERED`, `CART_CONVERTED`, `NONE`; per review **X1** the enum **ships without `CART_CONVERTED`** (`{CONTRACT_SIGNED, QUESTION_ANSWERED, NONE}`) until it's a genuinely distinct state.

### Catch-up window
- 🎓 After the mailroom was **closed for a day**, do you still send yesterday's reminders, or skip them as stale?
- 🛠️ `schedule_dispatch_max_catchup_minutes` (default 1440 = 24h). Occurrences older than that are `SKIPPED` "missed send window" (plan §4 item 3). Review **S3** says: one window for everything is too blunt. *(Landed: addendum §3 — per-rule `catchup_policy` SKIP/SEND + an alert on every skip; the 24 h default stays as the SKIP threshold; residual decision = ADD-Q2.)*

### 10DLC / TCPA / quiet hours (SMS only)
- 🎓 The **legal rules for texting** people in the US: you must register your business, honour opt-outs, and not text at night. Registering is slow paperwork — like a telegraph-office licence — so it's filed on **day one** of the build.
- 🛠️ A2P 10DLC brand+campaign registration, TCPA consent, state-aware quiet hours. Review **M2** — the SMS compliance surface, under-specified in the plan when SMS was deferred. *(Landed: fully specced in the SMS implementation plan's compliance substrate; 10DLC registration is the combined release's day-one long pole — carriers block 100% of unregistered traffic, so no production SMS before it's approved.)*

---

## New since 2026-07-08 — combined-release terms

The seven combined-release documents introduced a second vocabulary. Same format: plain first, technical second. The full story is [file 8](08_THE_COMBINED_RELEASE.md).

### Combined release
- 🎓 The decision that the mailroom **no longer opens alone**: the address-book department (DRR) and the telegram desk (SMS) open **in the same release**, sharing one address-lookup counter and one logbook.
- 🛠️ Scheduling (76.6/77.8) + DRR (77.9) + SMS (76.8) shipping together on a shared spine: ONE recipient-resolution engine, ONE `NotificationLog` migration, the D1 timing contract. Anything duplicating the resolver or adding a second log/occurrence table violates the release constraint (spine, "The release rule").

### Integration spine
- 🎓 The **one master plan the release runner reads**: what the three departments share, who builds what in which order, and the inspection sheet that says when the doors may open.
- 🛠️ `EMAIL_SMS_COMBINED_RELEASE_INTEGRATION_SPINE.md` — the cross-track contract: spec of record for the unified migration (§1.2) and the D1 toggle (§1.1.3), milestones MS0–MS9, the dependency matrix, the release-gate checklist (§4), and the conflict watch.

### Recipient-resolution engine (`RecipientResolutionService`)
- 🎓 The **one address-lookup counter** all three departments use. The mailroom's existing simple lookup ("the email written right on the cart") becomes the counter's simplest service tier — not a separate booth.
- 🛠️ Canonical in `background-worker-service/src/notification/recipient-resolution/`, native admin mirror kept identical by shared conformance vectors. The scheduler's restricted resolver is its **degenerate tier** (DRR DD-1); `destination:'email'|'phone'` with the phone path guard-rejected until SMS flips it; zero recipients → a `SKIP`/`ABORT` disposition, never a send (D3).

### `resolve_at_send` (the D1 toggle)
- 🎓 A per-instruction switch: **mail to the photocopy of the address list** made when the letter was written (default), or **check the address book again at mailing time** (opt-in, for rules where freshness matters more than predictability).
- 🛠️ `notification_schedules.resolve_at_send Boolean NOT NULL DEFAULT false` (spine §1.1.3; DRR DD-5). Default replays `recipients_snapshot` verbatim, byte-identical to today; `true` stores a reference shape and re-resolves inside the dispatch claim — exactly one new dispatcher branch. SMS inherits it with no variance.

### Open-questions register
- 🎓 The **filing cabinet of every unanswered question**: each card has a number that never changes, the person who owes the answer, tick-box options with our recommended default pre-marked, and what work waits on it. The build proceeds on the defaults; answers confirm or redirect.
- 🛠️ `EMAIL_SMS_COMBINED_RELEASE_OPEN_QUESTIONS.md` — 44 open entries (65 stable IDs counting the appendix's closed/carried rows), 8 categories A–H, answered in tier order (Tier 0 first: SMS-02, SMS-01, D1, SPINE-Q1). Supersedes the review-era "save it for the BA" guidance.

### Suppression store
- 🎓 The telegram desk's **do-not-wire list**. Anyone who says "stop" — by any reasonable means, not just the magic word — goes on it, and the desk checks the list before every single telegram.
- 🛠️ A platform-owned opt-out table (`sms_suppressions`, keyed by E.164 phone) checked pre-send on every dispatch, fed by the Twilio STOP webhook and manual capture, beside append-only consent events retained ≥ 5 years (SMS plan, compliance substrate — M2's landing).

### Gate / un-gate
- 🎓 The plan's "not yet" **fences**: letters for the closed departments were still written out, then stamped "skipped — department not open." **Un-gating** is lifting a fence when its department opens — no letters need rewriting, they just stop being skipped.
- 🛠️ The materialize-then-SKIP mechanism (plan §4 items 7/10). Un-gates are send-time flips, no schema change: the token-recipient gate lifts when the DRR engine deploys (MS6); the SMS gate via the H1 code flip + launch toggle at MS9 (spine §1.3).

### Dark flip vs. launch toggle (SMS)
- 🎓 Two different switches: **wiring the telegram desk up and inspecting it** with the shutter still down (dark flip), and **opening the shutter to the public** (launch toggle). With the shutter down, would-be telegrams are logged as "skipped — sending disabled": observable, harmless.
- 🛠️ The **H1 code flip** deploys the SMS dispatch branch dark (remove the SKIP pass, widen the select, extend the by-id channel assertion). **Launch** is `ppl_settings sms_sending_enabled='true'` (default `'false'`) — a settings edit + SQS invalidate, no deploy; gated on 10DLC + provisioning + consent, and the fastest rollback lever (spine §1.3).
