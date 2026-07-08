# 4. Doing it exactly once (and not overflowing)

← prev: [The three kinds](03_THE_THREE_KINDS.md) · next: [Time and who](05_TIME_AND_WHO.md)

**This file holds the single most important review finding — S1** — and, as of 2026-07-08, its concrete fix: each finding below now carries a **📦 WHERE IT LANDED** box pointing at the combined-release doc that turned it into buildable spec.

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

> **📦 WHERE IT LANDED — (combined-release docs, 2026-07-08)** — The mailroom gets its shredder: the retention cron is now fully specced — daily, and shipping *before* Phase 3, exactly as the review demanded. [Scheduling Fixes Addendum §1](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_SCHEDULING_FIXES_ADDENDUM.md) defines it as the same Registrar→Task→Service triple, daily off-peak (`0 30 3 * * *`), batch-deleting terminal rows (`SENT/SKIPPED/CANCELLED/FAILED` past the window — `PENDING`/`SENDING` never touched) with **three new `ppl_settings` keys**: `schedule_occurrence_retention_days` (default 90, clamp [7,365]), `schedule_retention_batch_size` (5000, [500,20000]), `schedule_retention_max_batches_per_run` (20, [1,100]) — the review's ALL-CAPS knob normalized to the plan's lower-snake convention (addendum §0.4). It adds one subtlety the review didn't have to solve: the **FOLLOW_UP latest-SENT-row purge guard** — per live series (`schedule_id` + `anchor_instance_ref`), the row with the highest `sequence_index` is excluded from deletion while the schedule is still enabled, because re-enqueue reads `series_anchor_at` from the prior occurrence; the shredder is taught never to shred the newest letter of a still-running follow-up chain. v1 is delete-only (SENT rows already link to `NotificationLog`, so no separate archive step). Slot: **MS4** in the [integration spine](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_INTEGRATION_SPINE.md), with a release-gate B checklist line ("S1 retention cron live before Phase 3 ships, with the FOLLOW_UP latest-row guard"). No open decision. The approved plan itself stays byte-for-byte untouched — where the addendum conflicts with the plan text, the addendum wins.

**Why this is the headline fix:** it's the only item that is *net-new engineering the plan doesn't mention at all*, and left out it becomes an operational problem in production, not a design flaw you'd catch in review later.

---

## S2 (Medium) — "exactly-once" is really "at-least-once"; say so

🎓 **For the newcomer.**
The supervisor who rescues abandoned letters has a rare downside: if a clerk was just **slow** (not crashed) and the supervisor rescues the letter, it can get mailed **twice**. True "never twice" is extremely hard; almost every real system is honestly "we'll never *fail* to send, but a rare retry might duplicate." The fix is mostly **to admit this in writing** and, if desired, add a safety catch later.

🛠️ **For the engineer.**
The genuine residual risk is the **reaper-vs-slow-send double-send**: the reaper flips a still-in-flight `SENDING` row back to `PENDING`, a later tick re-dispatches, and **SendGrid has no idempotency key by default** → two emails. The `dedupe_key` dedupes *materialization*, not *dispatch*.

> **📘 THE PLAN** — leans on single-instance topology as the cross-process guard; implies exactly-once.

> **🔎 THE REVIEW — `[S2 · Medium]`.** (1) Adopt `SELECT ... FOR UPDATE SKIP LOCKED` for the claim so correctness stops depending on deployment topology. (2) **State explicitly that the system is at-least-once, not exactly-once**, and that the reaper race is the accepted tail risk. (3) If you want a stronger guarantee later, add a SendGrid idempotency mechanism or a `NotificationLog` pre-insert keyed on `dedupe_key`. For transactional-email volume, at-least-once is usually fine — *just make it a stated decision, not an implied guarantee.*

> **📦 WHERE IT LANDED — (combined-release docs, 2026-07-08)** — Both refinements were adopted: the clerks now grab letters through a lock that works no matter how many mailrooms are running, and the paperwork says out loud that a rare retry may duplicate. [Scheduling Fixes Addendum §2](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_SCHEDULING_FIXES_ADDENDUM.md) makes the claim the Postgres-native outbox pattern inside one `prisma.$transaction`: `SELECT id … WHERE status='PENDING' … FOR UPDATE SKIP LOCKED`, then `UPDATE … SET status='SENDING' WHERE id=ANY(:ids) AND status='PENDING'` (the original atomic-update guard kept as belt-and-braces); sends happen only **after** the claim transaction commits. The **SKIP LOCKED claim is LOCKED in** — release-gate B requires it "in the first dispatch implementation" — so correctness no longer depends on `instances:1, maxSurge:0` topology (kept as defense-in-depth only). The **at-least-once statement is now explicit**, recorded verbatim in the dispatch service's doc-comment and the story's non-functional notes; `schedule_sending_stale_minutes=15` stays, with a documented floor (must exceed worst-case send + full batch, ≈ 8–9 min). What stays open is item (3): **ADD-Q1** in the [open-questions register](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_OPEN_QUESTIONS.md) (section E, Tier 3, owner Tech Lead + BA) asks whether to accept at-least-once or build provider-side idempotency (SendGrid idempotency / `NotificationLog` pre-insert on `dedupe_key`) now — **default if unanswered: accept at-least-once**, matching the review's own "usually fine at this volume" call. No send-side dedupe is built in this release. Slot: **MS4** (Phase 3 dispatch).

---

## S7 (Low) — personal data sits in the snapshot

🎓 Each planned letter carries a **photocopy of the recipient's details**. That's fine and necessary — but combined with "records are never shredded" (S1), personal data lingers indefinitely. Fix S1 and this bounds itself.

🛠️ `recipients_snapshot` stores PII so dispatch never needs a live recipient lookup (originally framed as the no-DRR ship path; snapshot-at-materialize remains the default even now that DRR ships — see the 📦 box). Acceptable; becomes properly time-bounded once **S1 retention** lands. Tie snapshot lifetime to the retention window; note the data-minimization rationale. No separate work beyond S1.

> **📦 WHERE IT LANDED — (combined-release docs, 2026-07-08)** — Closed by S1, exactly as predicted — no separate engineering, just the lifetime tie made explicit in writing. [Scheduling Fixes Addendum §7](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_SCHEDULING_FIXES_ADDENDUM.md) records the binding beside the retention job: `recipients_snapshot` lives exactly as long as its occurrence row — at most `schedule_occurrence_retention_days` (90) past terminal status — so **the purge IS the PII-minimization mechanism**. It rides **MS4** in the same PR as the S1 cron. The bookkeeping is tracked as the SCH-3 note under the **M1** entry in the [open-questions register](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_OPEN_QUESTIONS.md) (user-applied — the base registers are frozen to this pipeline); that note also records that the snapshot's *staleness* half is answered by D1's per-rule `resolve_at_send` toggle (default snapshot-at-materialize), owned by the DRR plan and integration spine. One fact has moved since this guide was written: SMS is no longer parked — it ships in this combined release, so the snapshot will also carry **phone numbers** under the same 90-day bound (spine §1.1.3: "neither track may assume snapshots persist").

---

## Summary of this file's review findings

| ID | Severity | One line | Where it landed |
|---|---|---|---|
| **S1** | **HIGH** | No retention/purge for the high-volume occurrences table — add a batched cleanup cron (also fixes S7) | [Addendum §1](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_SCHEDULING_FIXES_ADDENDUM.md) — retention cron fully specced (3 `ppl_settings` keys + FOLLOW_UP latest-SENT-row guard); MS4, gate-B checklist item; no open decision |
| S2 | Medium | Exactly-once really depends on topology; adopt `SKIP LOCKED` and state at-least-once honestly | [Addendum §2](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_SCHEDULING_FIXES_ADDENDUM.md) — `FOR UPDATE SKIP LOCKED` claim LOCKED in (gate B) + at-least-once stated verbatim; idempotency stays open as **ADD-Q1** in the [register](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_OPEN_QUESTIONS.md) (default: accept at-least-once) |
| S7 | Low | PII in the snapshot — bounded automatically once S1 lands | [Addendum §7](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_SCHEDULING_FIXES_ADDENDUM.md) — closed by S1; 90-day lifetime tie documented; tracked via the M1/SCH-3 register note (now covers SMS phone PII too) |
