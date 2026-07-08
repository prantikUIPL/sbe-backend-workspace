# 7. The review scorecard — every finding, the fix order, the open questions

← prev: [SMS and loose ends](06_SMS_AND_LOOSE_ENDS.md) · next: [The combined release](08_THE_COMBINED_RELEASE.md) · back to the [README](README.md)

This is the one-page reference. If you read nothing else, read this.

---

## The verdict

> **"The plan is sound and above the bar for this class of feature. Approve to build, incorporating the fixes below."**

No redesign. 16 findings, only **3 HIGH** plus one weighty Medium sequenced with them. One is net-new engineering (**S1**), one is a five-minute doc fix (**M1**), one converts your hardest open question into a switch (**D1**), one is a fail-closed safety change (**S6**, formally graded Medium).

> **📦 WHERE IT LANDED — (combined-release docs, 2026-07-08)** — Every finding on this page now has a concrete home. The mailroom didn't just get its inspection report — the work orders are written, numbered, and pinned to the wall. Seven combined-release documents were generated, verified (15 defects caught and fixed in verification) and committed under [`email_and_sms_docs/email_sms_combined_release_docs/`](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_INTEGRATION_SPINE.md): the scheduling-side findings became concrete deltas in the [fixes addendum](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_SCHEDULING_FIXES_ADDENDUM.md) (the approved plan stays byte-for-byte untouched; where they conflict, the addendum wins), the DRR/SMS findings became design decisions in the two implementation plans, the cross-doc items landed in the [integration spine](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_INTEGRATION_SPINE.md), and every open decision has an ID, an owner, and a built default in the [open-questions register](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_OPEN_QUESTIONS.md). The new "Where it landed" column below says exactly where each one went.

---

## All 16 findings at a glance

| ID | Area | Severity | What the plan does | What the review wants | Where it landed |
|---|---|---|---|---|---|
| **S1** | Scheduling | **HIGH** | Bounds future growth; never purges finished rows | Add a batched retention/purge cron (`SCHEDULE_OCCURRENCE_RETENTION_DAYS≈90`); archive to `NotificationLog` if needed. Also fixes S7. | Addendum §1 (knob normalized to `schedule_occurrence_retention_days`) · spine MS4 (before Phase 3 ships) |
| S2 | Scheduling | Medium | Leans on single-instance topology; implies exactly-once | Use `SELECT … FOR UPDATE SKIP LOCKED`; **state at-least-once explicitly**; optional provider idempotency later | Addendum §2 · **ADD-Q1** in the register |
| S3 | Scheduling | Medium | One global 24 h catch-up skip for all kinds | Make catch-up per-kind/per-rule (`SKIP`/`SEND`); at minimum alert on every skip | Addendum §3 (`catchup_policy` column) · **ADD-Q2** in the register |
| S4 | Scheduling | Medium | "RECURRING until answered" — no discovery query, stop-table not modelled | **Defer** that template with the other deferred deps (or specify query + require `end_window_at`) | Addendum §4 — deferred · **ADD-Q3** in the register |
| S5 | Scheduling | Low | Handles DST fall-back; tests only the gap | Add a unit test for the ambiguous fall-back hour | Addendum §5 (test task, Phase 3/4) |
| **S6** | Scheduling | **Medium** | Invalid event zone → default + warn, then send | Validate to IANA at ingest; **fail closed** (skip + alert) at send | Addendum §6 · spine MS4 (before Phase 3 ships) |
| S7 | Scheduling | Low | PII in `recipients_snapshot`, no retention tie-in | Bounded automatically once S1 lands; tie lifetime to retention | Addendum §7 — closed by S1, lifetime documented |
| **D1** | DRR | **HIGH** | Carried resolve-timing as a blocking conflict (DRR-13) | Make it a **per-rule toggle**; default = snapshot (scheduler already does this) | **Adopted** — DRR plan DD-5 + spine §1.1.3 (`resolve_at_send`) |
| D2 | DRR | Medium | `Exhibitor.company_id @unique` in schema, non-unique in DB | Drop `@unique` now — standalone fix, independent of DRR *(review said "both schema files"; recon found it in **all five**)* | Addendum §10 — five-schema fix · spine MS1 · register §G |
| D3 | DRR | Medium | Zero-recipient fallback left "subject to R&D" | Skip-and-log for marketing; **abort-and-alert for transactional**; never send to zero | DRR plan DD-6 (disposition + `is_transactional` flag) |
| **M1** | SMS | **HIGH** | Register says SMS "already built, zero schema change" | Correct to "SMS create is gated; storage shape undefined" — before the client sees it | Register §H entry **M1** — 3 tracked sub-items, user-applied |
| M2 | SMS | Medium | Quiet hours "8–9", leans on provider for STOP | Scope 2026 rules: state-aware hours, platform suppression store, 5-yr consent, 10DLC block gate | SMS plan compliance substrate (DD-8/DD-9, steps D1–D2) |
| M3 | SMS | Medium | `NotificationLog` has one `email` column, no channel | Add `channel` + generalized recipient column **before** any SMS dispatch | Spine §1.2 — the ONE unified migration (executed at MS3) |
| M4 | SMS | Low | SMS↔DRR circular (both deferred at review time, DRR email-only) | Sequence email DRR first; SMS reuses it extended to a phone field | Spine build order — MS5 dark build → MS6 email DRR → MS8 phone |
| X1 | Cross-doc | Low | `CONTRACT_SIGNED` & `CART_CONVERTED` are aliases today | Drop `CART_CONVERTED` from the enum until a distinct state exists | Addendum §8 — enum ships without it at Phase 1 (MS2) |
| X2 | Cross-doc | Low | Verification list thorough but pre-dates these fixes | Add retention / reaper-double-send / bad-timezone cases | Addendum §9 — the 3 cases, release-gate B checklist items |

Guide file for each: S1/S2/S7 → [file 4](04_DOING_IT_EXACTLY_ONCE.md) · S3/S4 → [file 3](03_THE_THREE_KINDS.md) · S5/S6/D1/D2/D3 → [file 5](05_TIME_AND_WHO.md) · M1–M4/X1/X2 → [file 6](06_SMS_AND_LOOSE_ENDS.md).

Landing docs (all in `../email_and_sms_docs/email_sms_combined_release_docs/`): **addendum** = [scheduling fixes addendum](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_SCHEDULING_FIXES_ADDENDUM.md) · **DRR plan** = [77.9 implementation plan](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_77.9_DRR_IMPLEMENTATION_PLAN.md) · **SMS plan** = [76.8 implementation plan](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_76.8_SMS_IMPLEMENTATION_PLAN.md) · **spine** = [integration spine](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_INTEGRATION_SPINE.md) · **register** = [open-questions register](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_OPEN_QUESTIONS.md).

---

## The recommended fix order (review Section 5)

🎓 **For the newcomer** — *do the text fix today; do the safety and cleanup work while building the engine; save the "who decides?" questions for the business analyst.*

🛠️ **For the engineer:**

1. **Before Phase 3 ships:** **S1** (retention job), **S6** (timezone fail-closed), **M1** (doc correction — do immediately, it's a text edit).
2. **During Phase 3/4:** S2 (`SKIP LOCKED` + at-least-once statement), S3 (catch-up policy + alerting), S4 (defer or specify "until answered"), X1 (drop enum value), X2 (tests).
3. **Decoupled, do soon:** D2 (drop `@unique` drift) — independent of DRR.
4. **Feed into BA/client sessions (no build yet):** **D1** (per-rule resolve toggle), D3 (transactional zero-recipient policy), M2 (2026 compliance scope), M3 (`NotificationLog` shape), M4 (DRR-then-SMS sequence).

### Superseded: the build now follows the spine's milestone plan

🎓 **For the newcomer** — the four-step list above was the review's suggested order for one mailroom project; the combined release turned it into a construction schedule for three projects sharing one building, and that schedule now wins. The list stays here for the record.

🛠️ **For the engineer:** the [integration spine §2](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_INTEGRATION_SPINE.md) sequences the whole combined release as milestones **MS0–MS9**, and the review's order survives inside it: the "before Phase 3 ships" items (S1, S6) are pinned to **MS4** alongside S2/S3/S5/X2; X1 applies at **MS2** (Phase 1 migration); D2 is its own milestone (**MS1** — "decoupled, do soon", with a fallback into DRR Step 1 if it slips); and step 4's "feed into BA sessions" is superseded outright — those items are now **built or specced** (D1, D3, M2, M3, M4 all have plan sections, see the table above), with the remaining *decisions* filed as owned entries in the [register](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_OPEN_QUESTIONS.md) and the BA agenda dispatched at **MS0(b)**. Critical path: MS2 → MS4 → MS6 → MS8 → MS9. The Twilio/10DLC registration long pole runs off the code path but gates the final launch flip — it starts day one (MS0(a)).

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
- The materialize-then-SKIP gates for SMS and token recipients — now the *interim* boundaries until each track's un-gate milestone, no longer indefinite parking.
- The DRR/SMS gap analyses' discipline: evidence-backed, owner-tagged, decision-ready.

---

## The 3 open questions the review put back to *you* (Section 6) — each now has a home

None were blockers for the report — and none is a loose thread anymore. All three are tracked in the [open-questions register](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_OPEN_QUESTIONS.md), each with an owner, a tier, and a default that is already built:

1. **Exactly-once vs at-least-once (S2)** — *is at-least-once with the reaper tail-risk acceptable, or design provider-side idempotency now?* → **ADD-Q1** (register §E, Tier 3, Tech Lead + BA). Default if unanswered: **accept at-least-once** — the addendum states it verbatim in the dispatch service doc-comment; provider-side idempotency stays a bolt-on, and X2's double-send test grows a suppression check only if it's adopted.
2. **"Unanswered product questions" RECURRING (S4)** — *defer it, or must it ship this build?* → **ADD-Q3** (register §E, Tier 2, BA). Default: **defer** it with the show/workshop anchors, exactly as addendum §4 writes down; overriding to must-ship requires the answer table + instance-discovery query specced in writing first.
3. **Resolve-timing (D1)** — *adopt the per-rule toggle, or hold the pure snapshot model?* → **adopted in the plan, pending BA sign-off.** The per-rule `resolve_at_send` toggle (default = snapshot-at-materialize) is specced in the DRR plan (DD-5) and spine §1.1.3; the register carries it as **D1** (§F, Tier 0) so the BA session confirms "both, selectable" rather than being asked to design it.

🎓 **For the newcomer** — the review's homework has filed itself: what used to be "questions for the business analyst" are now numbered tickets with recommended answers already ticked in pencil.

---

## Where this leaves us

- **Design: approved — and the build around it is now fully specced.** On 2026-07-08 seven combined-release docs were generated, verified (15 defects caught and fixed in the verification pass) and committed: refined DRR + SMS stories, the DRR implementation plan (shared `RecipientResolutionService`, 122 h), the SMS implementation plan (Twilio `SmsService` + compliance substrate, 73 h), the integration spine (MS0–MS9 + release-gate checklist), the scheduling fixes addendum, and the open-questions register (44 open entries across 8 categories).
- **Every one of the 16 findings has a landing place** — see the table's new column. The approved scheduling plan itself stays byte-for-byte untouched; the addendum carries the deltas and wins where they conflict.
- **One release, three tracks.** Scheduling (76.6/77.8) ships together with DRR (77.9) and SMS (76.8) — SMS is no longer parked, and the materialize-then-SKIP gates are interim boundaries with named un-gate flips at MS6/MS9, not indefinite fences.
- **Next:** answer the **Tier-0 register questions** (SMS-02, SMS-01, D1, SPINE-Q1) and kick off the **Twilio account + A2P 10DLC registration on day one** — it is the release long pole; started late, it *becomes* the release date.

For the full detail behind any item, the source documents remain authoritative:
- Plan: `email_and_sms_docs/email_sms_scheduling_plan_and_supporting_docs/EMAIL_SMS_SCHEDULING_IMPLEMENTATION_PLAN.md`
- Review: `email_and_sms_docs/EMAIL_SMS_PLAN_VALIDATION_REPORT.pdf`
- Combined-release docs (2026-07-08): `email_and_sms_docs/email_sms_combined_release_docs/` — the [addendum](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_SCHEDULING_FIXES_ADDENDUM.md), [spine](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_INTEGRATION_SPINE.md), [register](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_OPEN_QUESTIONS.md), [DRR plan](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_77.9_DRR_IMPLEMENTATION_PLAN.md) + [story](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_77.9_DRR_REFINED_STORY.md), [SMS plan](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_76.8_SMS_IMPLEMENTATION_PLAN.md) + [story](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_76.8_SMS_REFINED_STORY.md)

next: [The combined release](08_THE_COMBINED_RELEASE.md)
