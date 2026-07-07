# 7. The review scorecard — every finding, the fix order, the open questions

← prev: [SMS and loose ends](06_SMS_AND_LOOSE_ENDS.md) · back to the [README](README.md)

This is the one-page reference. If you read nothing else, read this.

---

## The verdict

> **"The plan is sound and above the bar for this class of feature. Approve to build, incorporating the fixes below."**

No redesign. 16 findings, only **4 HIGH**. One is net-new engineering (**S1**), one is a five-minute doc fix (**M1**), one converts your hardest open question into a switch (**D1**), one is a fail-closed safety change (**S6**).

---

## All 16 findings at a glance

| ID | Area | Severity | What the plan does | What the review wants |
|---|---|---|---|---|
| **S1** | Scheduling | **HIGH** | Bounds future growth; never purges finished rows | Add a batched retention/purge cron (`SCHEDULE_OCCURRENCE_RETENTION_DAYS≈90`); archive to `NotificationLog` if needed. Also fixes S7. |
| S2 | Scheduling | Medium | Leans on single-instance topology; implies exactly-once | Use `SELECT … FOR UPDATE SKIP LOCKED`; **state at-least-once explicitly**; optional provider idempotency later |
| S3 | Scheduling | Medium | One global 24 h catch-up skip for all kinds | Make catch-up per-kind/per-rule (`SKIP`/`SEND`); at minimum alert on every skip |
| S4 | Scheduling | Medium | "RECURRING until answered" — no discovery query, stop-table not modelled | **Defer** that template with the other deferred deps (or specify query + require `end_window_at`) |
| S5 | Scheduling | Low | Handles DST fall-back; tests only the gap | Add a unit test for the ambiguous fall-back hour |
| **S6** | Scheduling | **Medium** | Invalid event zone → default + warn, then send | Validate to IANA at ingest; **fail closed** (skip + alert) at send |
| S7 | Scheduling | Low | PII in `recipients_snapshot`, no retention tie-in | Bounded automatically once S1 lands; tie lifetime to retention |
| **D1** | DRR | **HIGH** | Carried resolve-timing as a blocking conflict (DRR-13) | Make it a **per-rule toggle**; default = snapshot (scheduler already does this) |
| D2 | DRR | Medium | `Exhibitor.company_id @unique` in schema, non-unique in DB | Drop `@unique` from both schemas now — standalone fix, independent of DRR |
| D3 | DRR | Medium | Zero-recipient fallback left "subject to R&D" | Skip-and-log for marketing; **abort-and-alert for transactional**; never send to zero |
| **M1** | SMS | **HIGH** | Register says SMS "already built, zero schema change" | Correct to "SMS create is gated; storage shape undefined" — before the client sees it |
| M2 | SMS | Medium | Quiet hours "8–9", leans on provider for STOP | Scope 2026 rules: state-aware hours, platform suppression store, 5-yr consent, 10DLC block gate |
| M3 | SMS | Medium | `NotificationLog` has one `email` column, no channel | Add `channel` + generalized recipient column **before** any SMS dispatch |
| M4 | SMS | Low | SMS↔DRR circular (both deferred, DRR email-only) | Sequence email DRR first; SMS reuses it extended to a phone field |
| X1 | Cross-doc | Low | `CONTRACT_SIGNED` & `CART_CONVERTED` are aliases today | Drop `CART_CONVERTED` from the enum until a distinct state exists |
| X2 | Cross-doc | Low | Verification list thorough but pre-dates these fixes | Add retention / reaper-double-send / bad-timezone cases |

Guide file for each: S1/S2/S7 → [file 4](04_DOING_IT_EXACTLY_ONCE.md) · S3/S4 → [file 3](03_THE_THREE_KINDS.md) · S5/S6/D1/D2/D3 → [file 5](05_TIME_AND_WHO.md) · M1–M4/X1/X2 → [file 6](06_SMS_AND_LOOSE_ENDS.md).

---

## The recommended fix order (review Section 5)

🎓 **For the newcomer** — *do the text fix today; do the safety and cleanup work while building the engine; save the "who decides?" questions for the business analyst.*

🛠️ **For the engineer:**

1. **Before Phase 3 ships:** **S1** (retention job), **S6** (timezone fail-closed), **M1** (doc correction — do immediately, it's a text edit).
2. **During Phase 3/4:** S2 (`SKIP LOCKED` + at-least-once statement), S3 (catch-up policy + alerting), S4 (defer or specify "until answered"), X1 (drop enum value), X2 (tests).
3. **Decoupled, do soon:** D2 (drop `@unique` drift) — independent of DRR.
4. **Feed into BA/client sessions (no build yet):** **D1** (per-rule resolve toggle), D3 (transactional zero-recipient policy), M2 (2026 compliance scope), M3 (`NotificationLog` shape), M4 (DRR-then-SMS sequence).

---

## What is explicitly right — do NOT second-guess (review Section 4)

The reviewer listed these as correct so the fixes above read as polish, not alarm:

- Dedicated tables over JSON columns; JSON columns kept only as advisory author hints.
- **Stable `offset_key`/`sequence_index` identity**; PENDING-recompute / SENT-immutable split.
- Multi-offset look-ahead window; RECURRING bounded roll-forward; FOLLOW_UP fixed `series_anchor_at` so late sends don't drift.
- DST-correct wall-clock with `date-fns-tz` and IANA zones.
- The **restricted `recipient_source`/`replacements_map` resolver** (bare column or one documented hop + fixed transforms, validated at config and materialize time — no expression DSL, no eval). "The right security posture."
- `is_schedulable` marked (not inferred), gated by the `supports_scheduling` ceiling; all 18 seeded rows correctly `false`.
- **By-id `notificationTemplateId` dispatch** making known-issue #21 immunity true by construction.
- The materialize-then-SKIP gates for SMS and token recipients.
- The DRR/SMS gap analyses' discipline: evidence-backed, owner-tagged, decision-ready.

---

## The 3 open questions the review put back to *you* (Section 6)

None are blockers for the report — they're places where your intent changes the recommendation:

1. **Exactly-once vs at-least-once (S2)** — is at-least-once with the reaper tail-risk acceptable for these emails, or design provider-side idempotency in now?
2. **"Unanswered product questions" RECURRING (S4)** — defer it with the show/workshop anchors, or must it ship this build?
3. **Resolve-timing (D1)** — adopt the per-rule toggle as the recommendation to the BA, or hold the pure snapshot model and just document the staleness?

---

## Where this leaves us

- **Design: approved.** Build it.
- **One net-new engineering task:** S1 retention.
- **One do-it-now doc fix:** M1.
- **One elegant unblock:** D1 becomes a per-rule switch with a default you've already built.
- **A short BA/client agenda:** D1, D3, M2, M3, M4 — decisions, not code.

For the full detail behind any item, the two source documents remain authoritative:
- Plan: `email_and_sms_docs/email_sms_scheduling_plan_and_supporting_docs/EMAIL_SMS_SCHEDULING_IMPLEMENTATION_PLAN.md`
- Review: `email_and_sms_docs/EMAIL_SMS_PLAN_VALIDATION_REPORT.pdf`
