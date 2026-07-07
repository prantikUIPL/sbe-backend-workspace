# 2. The schedulable switch (and its master breaker)

← prev: [The big picture](01_THE_BIG_PICTURE.md) · next: [The three kinds](03_THE_THREE_KINDS.md)

---

## What it is

🎓 **For the newcomer.**
Not every letter *should* be schedulable. A "here's your password reset link" email must go out **instantly** — scheduling it for next week would be absurd (and the link would be dead). So the design puts **two safety switches** in front of scheduling:

- A **light switch on each letter template**: "this particular template is allowed to be scheduled." (`is_schedulable`)
- A **master breaker on the whole event type**: "events like this are even *eligible* to have scheduled letters at all." (`supports_scheduling`)

The light switch only does anything if the master breaker is on. This means no future colleague can accidentally schedule a password-reset email, because the *event type* itself has its breaker off — permanently.

🛠️ **For the engineer.** (plan §2.0)

- `NotificationTemplate.is_schedulable Boolean @default(false)` — a first-class, **marked** (never inferred) per-template flag. Placed beside `is_predefined`.
- `TriggerEvent.supports_scheduling Boolean @default(false)` — a code-controlled catalog gate on the ~21-row trigger table.
- **Net rule:** a template may be `is_schedulable=true` *only if* its trigger has `supports_scheduling=true`. The trigger flag is the **ceiling**; the template flag is the **switch**.

Why marked, not inferred from "does a schedule row exist?" — because the admin UI must gate the "Add schedule" affordance *before* any schedule is attached, and a template can legitimately be schedulable-but-not-yet-scheduled.

---

## Where the two switches live

```
trigger_event (supports_scheduling)      ← master breaker, code-owned, ~21 rows
        │  a template may flip its switch ON only if this breaker is ON
        ▼
notification_template (is_schedulable)    ← per-template light switch
        │  a schedule may attach only if this switch is ON
        ▼
notification_schedule                     ← the actual rule (inert until the switch is on)
```

---

## An important, deliberate choice: today, *nothing* is scheduled yet

🎓 **For the newcomer.**
The design ships all this machinery but leaves **every one of the 18 existing templates with its switch OFF**. That sounds odd, but it's intentional: none of the current emails is a genuine "send this on a schedule" email today — they're all instant reactions. So the engine ships as a *framework* plus a couple of worked examples, and a developer explicitly turns the switch on when they wire a real scheduled email later.

🛠️ **For the engineer.** (plan §2.0.4, §4.y)
The backfill promotes **zero** template rows (all 18 stay `false`). It *does* open `supports_scheduling=true` on six triggers where scheduling is conceptually valid against an anchor that exists — but even those seeded templates stay `is_schedulable=false`; the gate exists so a *future same-trigger custom template* can be wired without a schema change. The flag still ships first-class (the seeder sets it explicitly on every row).

---

## What the review said about this

> **📘 THE PLAN** — the marked `is_schedulable` switch, gated by the code-owned `supports_scheduling` ceiling; all 18 seeded rows correctly ship `false`; by-id dispatch of a specific template.

> **🔎 THE REVIEW** — **approved, keep as-is.** Section 4 ("What is explicitly right") calls out by name: *"`is_schedulable` marked (not inferred), gated by the `supports_scheduling` trigger ceiling; all 18 seeded rows correctly false"* and *"by-id `notificationTemplateId` dispatch making known issue #21 immunity true by construction."* No change requested here.

**This is one of the areas the reviewer told us *not* to second-guess.** The only nearby cleanup is a tidy-up to the list of stop-reasons (finding **X1**), covered in [file 6](06_SMS_AND_LOOSE_ENDS.md).
