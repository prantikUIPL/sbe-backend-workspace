# 1. The big picture

← back to the [README](README.md) · next: [The schedulable switch](02_THE_SCHEDULABLE_SWITCH.md)

---

## The problem we're solving

🎓 **For the newcomer.**
Today the system sends emails only as an instant *reaction* — you place an order, an "order confirmation" email fires immediately. What it **cannot** do is send an email *on a future schedule*: "remind this customer 3 days before their cart expires," or "chase an unsigned contract every week until they sign," or "send a weekly digest every Monday at 9 AM." Building that automatic, time-based mailroom is the whole project.

🛠️ **For the engineer.**
The existing notification path is trigger-driven and synchronous (`MailerService.sendFromTemplate` fired from a live code site). There is no persisted send-schedule, no future-dated queue, and no poller that materializes time-relative sends. This plan adds a scheduling engine spanning `admin-backend-api` (configuration) and `background-worker-service` (execution), reusing the existing cron, `date-fns-tz`, SQS-refresh, and mailer machinery (plan §1, §6).

---

## The shape: three layers

🎓 **For the newcomer.** Think of three rooms:

1. **The office** where a manager writes the standing instructions ("remind 3 days before expiry").
2. **The mailroom** where clerks, every few minutes, write out the actual letters that are coming due and drop the due ones in the mailbox.
3. **The logbook** that records every letter that went out.

The office and the mailroom are different buildings (different services), connected by a **note passed between them** so that when the manager changes an instruction, the mailroom hears about it without anyone rebooting.

🛠️ **For the engineer.**

```
  ADMIN-BACKEND-API                    BACKGROUND-WORKER-SERVICE
  ┌───────────────────────┐           ┌──────────────────────────────────┐
  │ notification-template │   SQS     │ schedule-dispatch module          │
  │  module (CRUD)        │  refresh  │  Registrar → heartbeat cron       │
  │  + is_schedulable     │ ────────► │  Task      → re-entrancy + log    │
  │  + schedule DTOs      │           │  Service   → materialize+dispatch │
  └──────────┬────────────┘           └───────────────┬──────────────────┘
             │ writes                                  │ reads rules / writes occurrences
             ▼                                         ▼
        Postgres:  notification_schedules ──< notification_schedule_occurrences
                                                       │ dispatch via
                                                       ▼  MailerService.sendFromTemplate()
                                                    NotificationLog (PENDING→SENT/FAILED)
```

- **Config** lives in `admin-backend-api`; on save it publishes an **SQS refresh** so the worker reloads live (satisfies "dynamic, reflects without redeploy"). Plan §1.
- **Executor** lives in `background-worker-service` — the only service with `@nestjs/schedule`, `cron`, `date-fns-tz`, and the mailer. A single **heartbeat cron** materializes and dispatches. Plan §1, §4.
- **Source of truth** for schema/migrations is `admin-backend-api`; the other four services mirror via `db push`. Plan §2.

---

## How one scheduled email actually flows

🎓 **For the newcomer.** Follow one reminder from birth to mailbox:

1. A manager marks a letter template **"allowed to be scheduled"** and writes the rule: *"3 days and 1 day before a cart's expiry, at 9 AM."*
2. Every few minutes a clerk looks at carts expiring soon and **writes out the individual reminder letters** for each one, stamping each with a serial number and a "send on" date.
3. When a letter's "send on" date arrives, a clerk **grabs it** (so no colleague grabs the same one), **mails it**, and **records it in the logbook**.
4. If the cart gets signed early, the standing instruction says **stop** — any not-yet-mailed reminders for that cart are shredded.

🛠️ **For the engineer.** (plan §4.3)

1. Admin sets `is_schedulable=true` and creates a `notification_schedules` row (kind `ANCHOR_RELATIVE`, anchor `Cart.expiration_date`, offsets `-3d/-1d`, `send_time 09:00`, an IANA zone). SQS refresh fires.
2. Each tick the worker selects carts inside the look-ahead window and **upserts** one PENDING occurrence per (rule, cart, offset), keyed by a stable `dedupe_key`, with a DST-correct `fire_at` and a `recipients_snapshot` resolved from the cart row.
3. Due occurrences are **atomically claimed** (`PENDING→SENDING`), dispatched by explicit template id, linked to a `NotificationLog`, and marked `SENT`. Failures retry with backoff; crashes self-heal via the reaper.
4. A stop-condition resolver (`CONTRACT_SIGNED`) runs *before* dispatch each tick and `CANCEL`s remaining PENDING occurrences for a signed cart.

---

## The verdict on all of this

> **📘 THE PLAN** — everything above: the 3-layer shape, materialize-then-dispatch, stable identity, claim/reaper, DST-correct time, stop-conditions, and shipping *around* the two deferred pieces (SMS and DRR) with hard mechanical gates.

> **🔎 THE REVIEW** — **"The plan is sound and above the bar for this class of feature. Approve to build."** The core engineering shape is *correct by industry standards and needs no redesign.* The reviewer explicitly praised: materializing occurrences with a **non-time identity** ("the subtle detail most teams get wrong"), the atomic-claim + reaper + retry outbox mechanics, the DST-correct wall-clock, and the by-id dispatch that makes a known bug (#21) "immune by construction." The two gap analyses (SMS, DRR) were called "genuinely strong… decision-ready."

**So what follows is a fix-list, not an alarm.** None of it invalidates the architecture. The rest of this guide walks each area and shows exactly what the review wants added or changed.

**The single most important addition** is one the plan simply didn't include — see [file 4: Doing it exactly once](04_DOING_IT_EXACTLY_ONCE.md), finding **S1**.
