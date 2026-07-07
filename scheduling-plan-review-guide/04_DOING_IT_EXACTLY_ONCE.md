# 4. Doing it exactly once (and not overflowing)

← prev: [The three kinds](03_THE_THREE_KINDS.md) · next: [Time and who](05_TIME_AND_WHO.md)

**This file holds the single most important review finding — S1.**

---

## The hardest promise: send each thing exactly once

🎓 **For the newcomer.**
The scariest bug in a mailroom is **mailing the same reminder twice** (annoying, looks broken) — or **losing one entirely** (customer misses a deadline). The plan defends against both with three tricks:

1. **A serial number on every letter** so a duplicate letter is impossible to file.
2. **Grabbing a letter before working on it** so two clerks can't mail the same one.
3. **A supervisor who rescues abandoned letters** if a clerk crashes mid-task.

🛠️ **For the engineer.** (plan §2.2, §4 item 3, §4.3)

1. **Stable `dedupe_key` (`@unique`).** Built from *stable* parts — `schedule_id + anchor_instance_ref + offset_key` (or `sequence_index` for FOLLOW_UP) — **never from `fire_at`**, because `fire_at` is derived and shifts under DST/edits. Re-running materialize can never produce a duplicate row.
2. **Atomic claim.** Dispatch does `updateMany WHERE {id, status:PENDING} SET status='SENDING'` — only one worker wins the row.
3. **SENDING-reaper.** Rows stuck in `SENDING` past `schedule_sending_stale_minutes` (15) reset to `PENDING` so a crash self-heals.

> **📘 THE PLAN** — the stable-key identity + atomic claim + reaper, plus a stated single-instance worker deployment (`instances:1, maxSurge:0`) as the cross-process guard.

> **🔎 THE REVIEW** — the *identity choice is explicitly praised* ("the subtle detail most teams get wrong"), and the claim/reaper mechanics "mirror the transactional-outbox playbook." Two refinements follow (S2), and one thing is missing entirely (S1).

---

## 🔴 S1 (HIGH) — the one real new gap: nothing ever deletes old rows

🎓 **For the newcomer.**
Every letter the mailroom produces leaves a record behind — and those records are **never shredded**. The plan carefully limits how far *ahead* it writes letters (so it never runs away into the future), but once a letter is sent, its record just… stays. Forever. Over months and years that filing cabinet fills up, searches slow down, backups bloat. This is the **most common omission in exactly this kind of system**, and it's the one genuinely new piece of engineering the review adds.

🛠️ **For the engineer.**
Forward growth *is* bounded well (`SCHEDULE_MATERIALIZE_HORIZON_DAYS=45`, `SCHEDULE_RECURRING_HORIZON_DAYS=14`, one-at-a-time recurring). But **nothing purges occurrences once they reach a terminal state** (SENT/SKIPPED/CANCELLED/FAILED) — on a BigInt-PK, explicitly "high-volume" table. Result: unbounded bloat, slow `(status, fire_at)` scans, heavy backups.

> **📘 THE PLAN** — bounds *future* creation carefully; has **no retention/purge job** for terminal rows. (The plan flags PII-in-snapshot as open in its §9, but no cleanup mechanism.)

> **🔎 THE REVIEW — `[S1 · HIGH]` — fix before Phase 3 ships.** Add a **second, low-frequency cron** (reuse the same registrar pattern) that **batch-deletes or archives** terminal-status occurrences older than a new `ppl_settings SCHEDULE_OCCURRENCE_RETENTION_DAYS` (suggest 90, clamped). Use **batched deletes** (`DELETE ... WHERE id IN (SELECT id ... LIMIT 5000)` in a loop), never one blocking delete. If any audit must live longer, archive to `NotificationLog` (already the permanent audit) before deleting. **This also fixes S7** (PII in the snapshot becomes time-bounded).

**Why this is the headline fix:** it's the only item that is *net-new engineering the plan doesn't mention at all*, and left out it becomes an operational problem in production, not a design flaw you'd catch in review later.

---

## S2 (Medium) — "exactly-once" is really "at-least-once"; say so

🎓 **For the newcomer.**
The supervisor who rescues abandoned letters has a rare downside: if a clerk was just **slow** (not crashed) and the supervisor rescues the letter, it can get mailed **twice**. True "never twice" is extremely hard; almost every real system is honestly "we'll never *fail* to send, but a rare retry might duplicate." The fix is mostly **to admit this in writing** and, if desired, add a safety catch later.

🛠️ **For the engineer.**
The genuine residual risk is the **reaper-vs-slow-send double-send**: the reaper flips a still-in-flight `SENDING` row back to `PENDING`, a later tick re-dispatches, and **SendGrid has no idempotency key by default** → two emails. The `dedupe_key` dedupes *materialization*, not *dispatch*.

> **📘 THE PLAN** — leans on single-instance topology as the cross-process guard; implies exactly-once.

> **🔎 THE REVIEW — `[S2 · Medium]`.** (1) Adopt `SELECT ... FOR UPDATE SKIP LOCKED` for the claim so correctness stops depending on deployment topology. (2) **State explicitly that the system is at-least-once, not exactly-once**, and that the reaper race is the accepted tail risk. (3) If you want a stronger guarantee later, add a SendGrid idempotency mechanism or a `NotificationLog` pre-insert keyed on `dedupe_key`. For transactional-email volume, at-least-once is usually fine — *just make it a stated decision, not an implied guarantee.*

---

## S7 (Low) — personal data sits in the snapshot

🎓 Each planned letter carries a **photocopy of the recipient's details**. That's fine and necessary — but combined with "records are never shredded" (S1), personal data lingers indefinitely. Fix S1 and this bounds itself.

🛠️ `recipients_snapshot` stores PII to enable the no-DRR ship path. Acceptable; becomes properly time-bounded once **S1 retention** lands. Tie snapshot lifetime to the retention window; note the data-minimization rationale. No separate work beyond S1.

---

## Summary of this file's review findings

| ID | Severity | One line |
|---|---|---|
| **S1** | **HIGH** | No retention/purge for the high-volume occurrences table — add a batched cleanup cron (also fixes S7) |
| S2 | Medium | Exactly-once really depends on topology; adopt `SKIP LOCKED` and state at-least-once honestly |
| S7 | Low | PII in the snapshot — bounded automatically once S1 lands |
