# Email & SMS Scheduling — Plan vs. Review, Explained

A learning guide to **two documents at once**:

1. **The original implementation plan** — how we designed the automatic email/SMS scheduling engine.
   (Source: `email_and_sms_docs/email_sms_scheduling_plan_and_supporting_docs/EMAIL_SMS_SCHEDULING_IMPLEMENTATION_PLAN.md`)
2. **The external validation report** — an independent reviewer's verdict and fix-list.
   (Source: `email_and_sms_docs/EMAIL_SMS_PLAN_VALIDATION_REPORT.pdf`)

This guide does **not** replace either document. It re-tells them side by side so you can see, for every idea, **what we planned** and **what the review wants changed** — without reading 550 lines of spec first.

---

## The one-line summary

> We designed a system that sends scheduled emails (e.g. "remind a customer 3 days before their cart expires").
> An independent reviewer read the whole design and said: **"Approve to build — it's above the bar. Fix this short list of things as you go."**
> There is exactly **one brand-new engineering gap** (old records are never deleted) and **one document to correct** before a client sees it. Everything else is polish or a question for the business analyst.

---

## How to read this guide — pick your track

Every concept is explained twice. Read whichever half fits you (or both).

| Badge | Track | Who it's for |
|---|---|---|
| 🎓 **For the newcomer** | Plain language, real-world analogy, zero web-tech assumed | A school/college student, a PM, a business analyst, anyone new |
| 🛠️ **For the engineer** | The real terms, tables, and file/section references | Someone who knows databases, queues, cron jobs, time zones |

**The newcomer track leans on one running analogy: an automated mailroom.** Learn it once (below) and every later idea has a shelf to sit on.

---

## How to tell the plan from the review — two fixed boxes

Wherever the two documents speak, you'll see these exact two callouts. Never guess which is which:

> **📘 THE PLAN** — This is what the *original implementation plan* designed. It is the thing being reviewed.

> **🔎 THE REVIEW** — This is what the *validation report* suggests doing. Each one is tagged with its finding ID and severity, e.g. `[S1 · HIGH]`.

**Severity, straight from the report:**
- **HIGH** = fix before that part ships.
- **Medium** = fix while building that part.
- **Low** = tidy-up / documentation.

---

## The running analogy: the automated mailroom

Picture a company mailroom that sends **reminder letters automatically**, with no human deciding each one.

| In the analogy | In the real system | Plain meaning |
|---|---|---|
| A **standing instruction** ("mail a reminder 3 days before any cart expires") | a **schedule** (`notification_schedules` row) | a rule for *when* to send |
| The **calendar event** the reminder hangs off (the expiry date) | an **anchor** (`Cart.expiration_date`, etc.) | the date the rule counts from |
| One **specific letter**, for one person, for one day | an **occurrence** (`notification_schedule_occurrences` row) | one concrete planned send |
| **Writing the letters out ahead of time** from the standing instruction | **materialize** | turning a rule into concrete planned sends |
| **Dropping letters in the mailbox** when their day comes | **dispatch** | actually sending |
| A **serial number** on each letter so you never mail two identical ones | the **dedupe key** | the "send this exactly once" guarantee |
| A **clerk grabbing a letter to stamp it** so no one else grabs the same one | **claiming** (status `SENDING`) | locking a send so it isn't done twice |
| A **supervisor** who returns un-stamped letters to the pile if a clerk vanished mid-task | the **reaper** | self-healing after a crash |
| **Shredding old delivered-letter records** so the cabinet doesn't overflow | **retention / purge** | deleting finished rows |

Keep this table open in a second tab. Every file below points back to it.

---

## Reading order

Short files, each one concept. Read top to bottom, or jump to what you need.

| # | File | What it covers | Review findings inside |
|---|---|---|---|
| 0 | [`00_GLOSSARY.md`](00_GLOSSARY.md) | Every term, defined twice (plain + technical) | — |
| 1 | [`01_THE_BIG_PICTURE.md`](01_THE_BIG_PICTURE.md) | The problem, the 3-layer shape, how one email flows end to end | the overall verdict |
| 2 | [`02_THE_SCHEDULABLE_SWITCH.md`](02_THE_SCHEDULABLE_SWITCH.md) | The on/off flag that decides what may be scheduled | (approved as-is) |
| 3 | [`03_THE_THREE_KINDS.md`](03_THE_THREE_KINDS.md) | The three flavours of schedule | S3, S4 |
| 4 | [`04_DOING_IT_EXACTLY_ONCE.md`](04_DOING_IT_EXACTLY_ONCE.md) | Never double-send, never lose one, never overflow | **S1**, S2, S7 |
| 5 | [`05_TIME_AND_WHO.md`](05_TIME_AND_WHO.md) | Time zones/DST, and figuring out who gets the message | S5, **S6**, **D1**, D2, D3 |
| 6 | [`06_SMS_AND_LOOSE_ENDS.md`](06_SMS_AND_LOOSE_ENDS.md) | Why SMS is parked, plus the small tidy-ups | **M1**, M2, M3, M4, X1 |
| 7 | [`07_THE_REVIEW_SCORECARD.md`](07_THE_REVIEW_SCORECARD.md) | Every finding in one table, the fix order, the 3 open questions | all 16 |

**Bold** finding IDs are the HIGH-severity ones — the four that matter most: **S1**, **S6**, **D1**, **M1**.

---

## If you only remember four things

1. **The design is approved.** No redesign. The hard parts (never double-send, correct time-of-day across daylight-saving) are done right.
2. **S1 is the one real new gap:** finished send-records are never deleted, so that table grows forever. Add a cleanup job.
3. **M1 is a five-minute doc fix with outsized impact:** one of our status notes overstates how "done" SMS is. Correct it before the client reads it.
4. **D1 turns our hardest open question into a simple switch:** "use the freshest recipient list, or a frozen snapshot?" → make it a per-rule toggle, default to the snapshot we already build.
