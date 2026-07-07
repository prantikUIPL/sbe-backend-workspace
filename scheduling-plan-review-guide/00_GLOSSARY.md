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
- 🛠️ A cleanup job that deletes occurrences in a terminal state (SENT/SKIPPED/etc.) after a retention window. **This is the one thing the plan is missing** — review finding **S1**.

### At-least-once vs. exactly-once
- 🎓 "At-least-once" = *we will never fail to send, but in a rare crash-and-retry you might get the same letter twice.* "Exactly-once" = *never zero, never two.* True exactly-once is very hard.
- 🛠️ The design is **at-least-once**: the reaper can re-dispatch a slow send. Review **S2** says: state this honestly and, if you want, add provider-side idempotency later.

### Time zone / DST
- 🎓 Making sure **"9 AM" means 9 AM in the recipient's city**, even across the spring/autumn clock change.
- 🛠️ Wall-clock computed in an IANA zone via `date-fns-tz`, stored as UTC (plan §4.3). `timezone='EVENT'` reads the zone off the anchor; otherwise an explicit zone is required.

### DRR — Dynamic Recipient Resolution
- 🎓 Figuring out **who the letter actually goes to** when the address isn't written plainly on the record — e.g. "the salesperson assigned to this account," which has to be looked up.
- 🛠️ Story 77.9. Resolving token recipients (`{salesperson}`, `{all customer contacts}`) at send time. **Deferred** — the scheduler ships without it by only handling recipients that are a plain column on the anchor row (plan §4 item 3).

### Snapshot (recipients_snapshot)
- 🎓 **Photocopying the address list at the moment you write the letter**, then mailing to that copy — even if the real list changes later.
- 🛠️ The resolved `{to[], cc[], bcc[], replacements}` frozen onto the occurrence at materialize/capture time, replayed verbatim at dispatch (plan §2.2). The alternative — re-resolve at send — is review finding **D1**.

### `is_schedulable` (the switch) / `supports_scheduling` (the ceiling)
- 🎓 A **light switch** on each letter template ("this one *may* be scheduled") and a **master breaker** on the event type ("events like *this* are even allowed to have scheduled letters"). The switch only works if the breaker is on.
- 🛠️ `is_schedulable` on `NotificationTemplate`; `supports_scheduling` on `TriggerEvent` (plan §2.0). A template may be schedulable only if its trigger allows it. See [`02_THE_SCHEDULABLE_SWITCH.md`](02_THE_SCHEDULABLE_SWITCH.md).

### The three kinds
- 🎓 Three flavours of standing instruction: **before/after a date** (ANCHOR_RELATIVE), **on a repeating calendar** (RECURRING), **a chase-up series** (FOLLOW_UP). See [`03_THE_THREE_KINDS.md`](03_THE_THREE_KINDS.md).
- 🛠️ Enum `NotificationScheduleKind { ANCHOR_RELATIVE, RECURRING, FOLLOW_UP }` (plan §2.1).

### Stop-condition
- 🎓 A reason to **stop chasing**: "keep reminding until the contract is signed — then stop."
- 🛠️ A code-controlled enum (`CONTRACT_SIGNED`, `QUESTION_ANSWERED`, `CART_CONVERTED`, `NONE`) evaluated each tick; resolved state cancels remaining PENDING occurrences (plan §4 item 4).

### Catch-up window
- 🎓 After the mailroom was **closed for a day**, do you still send yesterday's reminders, or skip them as stale?
- 🛠️ `schedule_dispatch_max_catchup_minutes` (default 1440 = 24h). Occurrences older than that are `SKIPPED` "missed send window" (plan §4 item 3). Review **S3** says: one window for everything is too blunt.

### 10DLC / TCPA / quiet hours (SMS only)
- 🎓 The **legal rules for texting** people in the US: you must register your business, honour opt-outs, and not text at night.
- 🛠️ A2P 10DLC brand+campaign registration, TCPA consent, state-aware quiet hours. Review **M2** — the SMS compliance surface, under-specified in the plan because SMS is deferred.
