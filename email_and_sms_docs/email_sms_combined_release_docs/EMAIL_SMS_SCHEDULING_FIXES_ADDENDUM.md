# Email & SMS Scheduling — Review Fixes Addendum (delta to the approved plan)

**DOC 6 of 7 — combined-release doc set** (`email_sms_combined_release_docs/`)
**Date:** 2026-07-08
**Base document (UNTOUCHED):** `email_and_sms_docs/email_sms_scheduling_plan_and_supporting_docs/EMAIL_SMS_SCHEDULING_IMPLEMENTATION_PLAN.md` (Revision 3, 2026-06-18)
**Review source:** *Email & SMS Management — Plan Validation Report* (external, 2026-07-07; full text preserved in the review-guide set, condensed scorecard at `APIs/scheduling-plan-review-guide/07_THE_REVIEW_SCORECARD.md`)
**Status:** delta spec, ready to apply during the build. No code or plan-file changes are made by this document.

---

## 0. Front matter

### 0.1 Purpose

The scheduling implementation plan was externally validated. Verdict, quoted:

> **"The plan is sound and above the bar for this class of feature. Approve to build, incorporating the fixes listed in Section 3."**

No redesign. 16 findings (S1–S7 scheduling, D1–D3 DRR, M1–M4 SMS, X1–X2 cross-doc), 4 HIGH (S1, S6, D1, M1). The approved plan file stays **byte-for-byte untouched** — that is a deliberate process decision: the plan is the reviewed, approved baseline; every review fix lands as a **delta section in this addendum**, and engineers apply the plan **plus this addendum** together during the build. Where an addendum section conflicts with the plan text it amends, **this addendum wins**.

### 0.2 Scope of this addendum — and what is deliberately NOT here

**In scope (the scheduling-track findings that are ours to build/fix inside the scheduling build):** S1, S2, S3, S4, S5, S6, S7, X1, X2 — plus **D2**, which the review explicitly directs to be done as a **standalone data-integrity fix decoupled from DRR** ("fix now… so it can't bite an unrelated query first"), and which therefore rides with this track's schema work rather than waiting for the DRR plan.

**Explicitly excluded (owned by the sibling docs in this folder — do not implement them from here):**

| Finding | Where it is handled |
|---|---|
| **D1** (resolve-timing per-rule toggle, default = snapshot-at-materialize) | The **integration-spine doc** (shared spine: one resolver, the D1 toggle) + the **DRR plan** — it is a combined-release spine decision, not a scheduling-only delta. |
| **D3** (zero-recipient fallback: skip-and-log for reminders, abort-and-alert for transactional) | The **DRR plan** (BA/client decision item). Its alerting reuses the S3 alert channel added here. |
| **M1** (correct the base register's "SMS already built" overstatement) | The SMS-side doc set. `EMAIL_SMS_KNOWN_ISSUES.md` is frozen/read-only for this track (plan §8, register-separation rule); the correction is proposed there, applied by the user. |
| **M2** (2026 SMS compliance: state-aware quiet hours, suppression store, 5-yr consent, 10DLC gate) | The **SMS provider integration plan**. |
| **M3** (unified `NotificationLog` migration: `channel` + generalized recipient) | The **integration-spine doc** — it is the ONE shared NotificationLog migration for the combined release (admin-owned, `db push` to the other four). This addendum does not add any NotificationLog columns. |
| **M4** (break the DRR↔SMS circularity: email DRR first, SMS reuses the same resolver extended to a phone field) | The **integration-spine doc** (sequencing) — one shared recipient-resolution engine, never a parallel resolver. |

**Release context (for orientation only):** scheduling (76.6/77.8), DRR (77.9) and SMS (76.8) ship **together as one combined release** with a shared spine (one resolver; one unified NotificationLog migration; the D1 per-rule resolve-timing toggle defaulting to snapshot-at-materialize). Nothing in this addendum forks that spine; the deltas below are engine-internal.

### 0.3 Summary delta table (finding → plan section amended → when it lands)

The review's own fix sequence (report §5) is preserved. "Phase N" refers to the plan's §7 phasing.

| ID | Severity | One-line | Plan section(s) amended | When |
|---|---|---|---|---|
| **S1** | **HIGH** | No retention/purge for `notification_schedule_occurrences` | §2.2, §4 (new cron beside the heartbeat), §6, §8 | **Before Phase 3 ships** |
| **S6** | Medium (fix-before-ship class) | Invalid `EVENT` timezone silently defaults → wrong-hour send | §4 item 11, §4.3, §8 | **Before Phase 3 ships** |
| S2 | Medium | Exactly-once leans on topology; reaper race can double-send | §4 item 3 (Dispatch), §4 item 3 (SENDING-reaper) | During Phase 3/4 |
| S3 | Medium | One-size 24h catch-up skip can drop a still-valid send | §2.1, §4 item 3 (Catch-up), §6 | During Phase 3/4 |
| S4 | Medium | RECURRING "until answered" has no instance-discovery query + deferred resolver | §4.3 (RECURRING), §4 item 4, §9 | During Phase 3/4 (as a **deferral**, option (a)) |
| S5 | Low | DST ambiguous (fall-back) case not explicitly unit-tested | §4.3 (DST), §8 | Test task, lands with Phase 3 tests |
| S7 | Low | PII in `recipients_snapshot` with no retention tie-in | §9 (FOLLOW_UP snapshot retention bullet) | **Closed by S1** — no separate work |
| X1 | Low | `CART_CONVERTED` aliases `CONTRACT_SIGNED` on today's schema | §2.1 (`stop_condition`), §4 item 4, §9 | During Phase 3/4 (Phase 1 enum ships without it) |
| X2 | Low | Verification list pre-dates these fixes | §8 | During Phase 3/4 (tests) |
| D2 | Medium | `Exhibitor.company_id @unique` schema-vs-DB drift is a latent bug beyond DRR | (not a plan section — a standalone schema fix across the five repos) | **Decoupled — do soon**, independent of every phase |

### 0.4 Conventions

- Plan terminology is used **exactly** (table/column/setting names: `notification_schedules`, `notification_schedule_occurrences`, `dedupe_key`, `recipients_snapshot`, `ppl_settings` keys in lower snake case, etc.). The review wrote setting names in caps (`SCHEDULE_OCCURRENCE_RETENTION_DAYS`); the plan's established convention is lower snake (`schedule_dispatch_interval_minutes`, plan §4 item 1 / §6), so all new keys below follow the plan's convention.
- Schema prefs apply throughout: **Int PKs** (the occurrence table's BigInt PK stays the one approved exception, plan §2.2), **NOT NULL + default/backfill** over nullable, **no raw-SQL-only schema constructs** (partial indexes) — but runtime `$queryRaw` in the worker is fine and is used deliberately in S2 (it is a query, not a schema construct, so sibling `db push` cannot drop it).
- `admin-backend-api` owns every migration; the other four mirror via `db push` (plan §2 / `CLAUDE.md`).
- Open decisions left by the review are tagged **ADD-Qn** with a clear question; they are the addendum's question register.

---

## 1. S1 — Retention/purge job for `notification_schedule_occurrences` (HIGH)

**(a)** S1 / HIGH / Nothing purges terminal-status occurrence rows — the explicitly "high-volume" BigInt-PK table grows forever.

**(b) Plan as written.** Forward growth is well bounded — `schedule_materialize_horizon_days` (45), `schedule_recurring_horizon_days` (14), one-occurrence-at-a-time RECURRING roll-forward (plan §4.3) — but no plan section deletes rows once they reach `SENT` / `SKIPPED` / `CANCELLED` / `FAILED`. Plan §2.2 defines the statuses and indexes; §6 lists the six `ppl_settings` knobs; none is a retention knob. The review calls this "the single most common omission in exactly this design."

**(c) The delta.**

1. **New job:** a second, low-frequency cron in the same `src/scheduler/schedule-dispatch/` module (or a sibling `schedule-retention/` folder — either way it reuses the identical Registrar → Task → Service triple, plan §4 preamble, cloned from `low-balance-scheduler.registrar.ts:34-60`). Suggested cron: daily off-peak, six-field `0 30 3 * * *`. Register it in `scheduler.module.ts` beside the heartbeat; give it its own `isRunning` re-entrancy guard and `ApplicationLogService` started/completed/failed lifecycle (same as the heartbeat Task, plan §4 item 2). Add its refresh method to the SQS `ModuleRegistry` allow-list so the knobs hot-reload like the others.
2. **New `ppl_settings` keys** (read via `PplSettingsService.getInt`, TTL cache + `invalidate` — plan §6):
   - `schedule_occurrence_retention_days` — default **90**, clamped `[7, 365]`.
   - `schedule_retention_batch_size` — default **5000**, clamped `[500, 20000]`.
   - `schedule_retention_max_batches_per_run` — default **20**, clamped `[1, 100]` (hard per-run ceiling so a first run against a long backlog cannot monopolize the DB; the remainder rolls to the next day).
3. **Batched delete, never one blocking DELETE** (the review's explicit pattern):

   ```sql
   -- one batch; loop until rowcount < batch_size or max_batches reached
   DELETE FROM notification_schedule_occurrences
   WHERE id IN (
     SELECT id FROM notification_schedule_occurrences
     WHERE status IN ('SENT','SKIPPED','CANCELLED','FAILED')
       AND updated_at < now() - make_interval(days => :retention_days)
     ORDER BY id
     LIMIT :batch_size
   );
   ```

   Run as `$executeRaw` from the worker service (runtime SQL — allowed; see §0.4). `PENDING` and `SENDING` rows are **never** touched.
4. **FOLLOW_UP series guard (build-critical interaction).** Plan §4 item 8 says re-enqueue "reads `series_anchor_at` from the prior occurrence." A naive purge of an old `SENT` occurrence in a still-live series would break the next re-enqueue. Therefore the delete predicate **excludes, per FOLLOW_UP series (`schedule_id` + `anchor_instance_ref`), the row with the highest `sequence_index`** whenever that series' schedule is `is_enabled = true` and the series has not terminated (stop resolved / `repeatCount` reached / `end_window_at` passed). Simplest correct form: for `schedule_kind = 'FOLLOW_UP'`, only delete a terminal occurrence if a **later** occurrence exists in the same series **or** its schedule is disabled/terminated. (Alternative — copy `series_anchor_at` forward onto every occurrence at insert — is already the plan's shape since each occurrence carries `series_anchor_at`; if the implementer confirms re-enqueue reads the *current* occurrence's own `series_anchor_at` rather than joining to the prior row, this guard reduces to documentation. Verify against the built code and keep whichever guard is true.)
5. **RECURRING watermark note.** The §4.3 watermark ("latest materialized `occurrence.fire_at`, else `schedule.created_at`") survives retention in the normal case because an active RECURRING schedule always has a PENDING row (never purged). In the pathological case (schedule disabled long enough for all rows to purge, then re-enabled), roll-forward restarts from `schedule.created_at` but the catch-up sweep (`schedule_dispatch_max_catchup_minutes`, plan §4 item 3) bounds any past-slot dispatch — so no delta needed beyond this documented note.
6. **Archive decision (v1 = delete-only).** `SENT` occurrences are already linked to the permanent audit (`notification_log_id` → `NotificationLog`, plan §2.2/§4 item 9), so deleting them loses no send audit. `SKIPPED`/`FAILED` reasons live only on the occurrence; the retention window (90 days) **is** their audit window. If the business later needs longer skip/fail forensics, the review's prescribed path is to archive into `NotificationLog` **before** deleting — do not build that until asked.

**(d) When:** **before Phase 3 ships** (review §5 step 1) — the retention cron must exist before the first tick can start accumulating terminal rows in production.

**(e) Open decision:** none. (The archive-vs-delete refinement above is a documented default, not a blocker.)

---

## 2. S2 — Claim via `SELECT … FOR UPDATE SKIP LOCKED`; state at-least-once explicitly (Medium)

**(a)** S2 / Medium / Exactly-once currently leans on single-instance topology; the reaper-vs-slow-send race can double-send, and SendGrid has no default idempotency key.

**(b) Plan as written.** Plan §4 item 3: dispatch selects due PENDING rows then claims each atomically (`updateMany WHERE {id, status:PENDING} SET status='SENDING', claimed_at=now()`, mirroring payment-charge `claimRow`); the SENDING-reaper resets rows stuck past `schedule_sending_stale_minutes` (default 15); and "the topology is the cross-process guard" (worker README §5: `instances:1, maxSurge:0`). The review notes: the atomic `updateMany` actually already holds under concurrency (the exposure is narrower than the plan implies), but `maxSurge:0` does not *guarantee* zero deploy overlap, and the genuine residual risk is the reaper flipping a still-in-flight `SENDING` row back to `PENDING` → second dispatch → recipient gets two emails. `dedupe_key` dedupes **materialization, not dispatch**.

**(c) The delta.**

1. **Claim pattern change (Phase 3 dispatch code).** Replace the plain select-then-claim with the Postgres-native outbox claim, composed with the existing status guard, inside one `prisma.$transaction`:

   ```sql
   -- step 1 (in txn): pick and row-lock candidates, skipping rows locked by any other process
   SELECT id FROM notification_schedule_occurrences
   WHERE status = 'PENDING' AND channel = 'EMAIL'
     AND fire_at <= now()
     AND fire_at >= now() - make_interval(mins => :max_catchup_minutes)   -- see S3 for the per-rule variant
     AND (next_attempt_at IS NULL OR next_attempt_at <= now())
   ORDER BY fire_at
   LIMIT :max_dispatch_per_run
   FOR UPDATE SKIP LOCKED;

   -- step 2 (same txn): claim exactly those ids, keeping the belt-and-braces status guard
   UPDATE notification_schedule_occurrences
   SET status = 'SENDING', claimed_at = now()
   WHERE id = ANY(:ids) AND status = 'PENDING';
   ```

   Actual sends happen **after** the claim transaction commits (never inside it — don't hold row locks across a SendGrid call). This is runtime `$queryRaw`/`$executeRaw` in `background-worker-service` only — it is not a schema construct, so the "avoid raw-SQL-only constructs" rule (plan §2.0.6) is not implicated. Correctness now no longer depends on deployment topology; keep `instances:1, maxSurge:0` as defense-in-depth, not as the guarantee.
2. **Keep `schedule_sending_stale_minutes = 15`, and document the floor** (amends the §4 item 3 reaper text): the value must stay comfortably above the worst-case single SendGrid call + network timeout, **and** above the expected duration of a full dispatch batch (`MAX_DISPATCH_PER_RUN = 500` sequential sends at ~1s worst-case ≈ 8–9 min < 15 min). Anyone lowering it must re-derive that bound; put this sentence in the code comment beside the constant.
3. **State the guarantee explicitly** (amends the plan's implied semantics): the system is **at-least-once, not exactly-once**. The reaper race (a genuinely slow-but-alive send being reaped and re-dispatched) is the **accepted tail risk** — a stated decision, not an implied guarantee. Record this sentence verbatim in the schedule-dispatch service doc-comment and in the story's non-functional notes.
4. **Do NOT build send-side dedupe now.** If a stronger guarantee is wanted later, the reviewed options are (i) a SendGrid idempotency mechanism, or (ii) a `NotificationLog` pre-insert keyed on `dedupe_key` acting as the send-side dedupe. Both are deferred pending ADD-Q1.

**(d) When:** during Phase 3 (the claim is written once, in the first dispatch implementation) — review §5 step 2.

**(e) Open decision — ADD-Q1 (maps to S2):** *Is at-least-once with the reaper tail-risk acceptable for these transactional-volume emails, or must a provider-side idempotency mechanism (SendGrid idempotency or a `NotificationLog` pre-insert keyed on `dedupe_key`) be designed in now?* Default if unanswered: accept at-least-once (the review states this is "usually acceptable" at this volume).

---

## 3. S3 — Per-rule catch-up policy + alert on every catch-up skip (Medium)

**(a)** S3 / Medium / The single global 24h catch-up window (`schedule_dispatch_max_catchup_minutes` = 1440) silently drops sends that are still valid late — right for proximity reminders, wrong for e.g. a payment-due reminder that came due during a 26h outage.

**(b) Plan as written.** Plan §4 item 3 "Catch-up after downtime": PENDING occurrences with `fire_at < now() - max_catchup_minutes` → `SKIPPED` reason "missed send window (downtime catch-up)", one global window for every kind, no alerting beyond the row's own status.

**(c) The delta.**

1. **New column on `notification_schedules`** (plan §2.1 table gains one row; admin migration + mirror to the four siblings + `db push`, per plan §2.0.6):

   | Column | Type | Notes |
   |---|---|---|
   | `catchup_policy` | enum `NotificationCatchupPolicy { SKIP, SEND }` **NOT NULL `@default(SKIP)`** | Per-rule policy for occurrences older than the catch-up window. NOT NULL + default per schema prefs; backfill is the default itself (no data exists yet — the table is new this release). |

   ```sql
   ALTER TABLE "notification_schedules"
     ADD COLUMN IF NOT EXISTS "catchup_policy" "NotificationCatchupPolicy" NOT NULL DEFAULT 'SKIP';
   COMMENT ON COLUMN "notification_schedules"."catchup_policy" IS
     'Downtime catch-up: SKIP = occurrences older than schedule_dispatch_max_catchup_minutes are marked SKIPPED (proximity reminders); SEND = still dispatch late (payment/contract reminders).';
   ```

2. **Executor behavior** (amends §4 item 3's sweep): the top-of-tick sweep only auto-SKIPs stale PENDING occurrences whose **rule** has `catchup_policy = 'SKIP'`. Rows on a `SEND` rule stay eligible and dispatch through the normal path — still subject to `MAX_DISPATCH_PER_RUN`, retry/backoff, and (critically) the stop-condition pass and the live-anchor reconcile (§4 item 4 / §4.3), which run **before** dispatch, so a late send against a since-resolved anchor is CANCELLED, not sent. The 24h `schedule_dispatch_max_catchup_minutes` default stays as the SKIP threshold, unchanged.
3. **DTO / validation:** `catchup_policy` is an optional field on `ScheduleRuleDto` (enum-validated, default `SKIP`), merged via the same `collectScalarUpdates`-style semantics and audited like every schedule field (plan §3 items 1–3).
4. **Alerting — a silent mass-skip must be visible.** Every occurrence the sweep skips writes a **warn-level** `ApplicationLogService` line; additionally the tick emits **one aggregate line** — `"catch-up sweep: skipped N occurrences across M schedules (window=1440m)"` — so a post-outage mass-skip appears as one findable event, not a thousand row updates. (D3's "abort-and-surface" alerting in the DRR plan reuses this same channel — pointer only, not built here.)

**(d) When:** during Phase 3 (the sweep is written in Phase 3; the column ships with the Phase 1 migration if convenient, else as a follow-on migration before Phase 3 completes) — review §5 step 2.

**(e) Open decision — ADD-Q2 (maps to S3):** *Choose the catch-up policy model: (A) a single default `SKIP` with the per-rule `catchup_policy` override as specced above, or (B) additionally apply per-kind DTO defaults (ANCHOR_RELATIVE proximity → `SKIP`; FOLLOW_UP / payment-anchored rules → `SEND`) so authors get the review's recommended behavior without thinking about it.* The review permits either ("either a per-kind default … or a per-rule catchup_policy"). Default if unanswered: (A) — one explicit column, no hidden kind-based behavior.

---

## 4. S4 — RECURRING "until answered": defer it with its deferred dependencies (Medium)

**(a)** S4 / Medium / The per-instance "until answered" RECURRING case has neither a defined instance-discovery query (which `order_product` rows currently need a series?) nor a live stop resolver (`QUESTION_ANSWERED` is `[dep]` — the answer table is not modelled).

**(b) Plan as written.** Plan §4.3 (RECURRING): per-instance series bound by `anchor_instance_ref='order_product:'+id`, one rolling occurrence at a time, stopped by the resolver or `end_window_at`. Plan §4 item 4: `QUESTION_ANSWERED` "parse `'order_product:ID'`, resolved when the count of unanswered dynamic product questions = 0. If the answer table is not yet modelled, mark `QUESTION_ANSWERED` **[dep]** and require the rule to carry an `end_window_at` fallback." The HARD RULE (§4 item 4 / §2.1.1) already forces a bound on any rule whose resolver is unimplemented. What is missing is the **start side**: no query enumerates which instances need a series.

**(c) The delta — adopt the review's option (a), the recommended one.**

1. **Defer the "unanswered product questions" RECURRING template** alongside the already-deferred show/workshop anchors (plan §9 gains it in the deferred list; it joins `Shows.date`, the workshop anchor, and the employee-date anchors as "engine supports it, data model does not yet"). It does **not** ship in Phase 4. This "keeps Phase 4 honest" (review wording) and matches how every other deferred-dependency anchor is handled.
2. **What still ships in Phase 4:** the per-instance RECURRING *mechanics* (per-instance `anchor_instance_ref`, one-at-a-time roll-forward, stop-on-resolve) remain in the code path exactly as §4.3 specifies — they are exercised by tests, not by a live client template. No instance-discovery query is invented for a table that does not exist.
3. **Config-time guard already covers the tail:** the HARD RULE stands unchanged — any rule authored with `stop_condition = QUESTION_ANSWERED` while the resolver is not in `IMPLEMENTED_STOP_RESOLVERS` MUST carry `end_window_at` or `repeatCount`, rejected otherwise. With option (a) this is belt-and-braces, since the template itself is deferred.
4. **If the business overrides to option (b) (must-ship):** the build must then (i) model/locate the answer table, (ii) define the enumerating query (the "which `order_product` rows have unanswered questions" discovery select) as a concrete spec in the story before coding, and (iii) keep the mandatory `end_window_at` until `QUESTION_ANSWERED` is in `IMPLEMENTED_STOP_RESOLVERS`. Do not start (b) without a written answer to ADD-Q3.

**(d) When:** during Phase 3/4 planning (it is a scope decision applied at Phase 4) — review §5 step 2.

**(e) Open decision — ADD-Q3 (maps to S4):** *Defer the "unanswered product questions" RECURRING template with the show/workshop anchors (review-recommended option (a)), or must it ship this build (option (b), which requires modelling the answer table + specifying the instance-discovery query + keeping the `end_window_at` bound)?* Default if unanswered: (a) defer.

---

## 5. S5 — Pin the DST fall-back (ambiguous hour) choice with a unit test (Low)

**(a)** S5 / Low / The plan handles both DST edges but the verification list only names a **gap** (spring-forward) test; the fall-back ambiguous-hour choice ("earlier instant") is unpinned by tests.

**(b) Plan as written.** Plan §4.3 (DST-correct wall-clock): "spring-forward nonexistent local time → normalize forward to the next valid instant; fall-back ambiguous time → choose the earlier (first) occurrence deterministically; add a unit test for a `send_time` landing in the DST gap." Plan §8: "**DST gap** — a `send_time` landing in the spring-forward gap normalizes forward…". Both design choices are fine (review confirms); only the second test is missing.

**(c) The delta.** Add one unit test beside the existing gap test in the Phase 3 test suite:

- **Ambiguous fall-back case:** a rule with `send_time = '01:30'`, `timezone = 'America/New_York'`, materializing for the fall-back date (e.g. 2026-11-01, when 01:00–02:00 EDT repeats as 01:00–02:00 EST). Assert the computed `fire_at` is the **earlier** instant — `2026-11-01T05:30:00Z` (01:30 **EDT**, UTC−4) — not `06:30:00Z` (01:30 EST, UTC−5), and that the choice is deterministic across repeated computation (idempotent `dedupe_key` upsert produces one row).

This is a test task only; no behavior change. (X2 §8 additions are listed separately in section 9.)

**(d) When:** lands with the Phase 3 DST tests (same PR as the materializer's wall-clock math).

**(e) Open decision:** none.

---

## 6. S6 — Event timezone: validate at ingest, fail CLOSED at send (Medium; fix before Phase 3 ships)

**(a)** S6 / Medium (sequenced with the HIGHs) / An invalid free-form `Shows.timezone` currently falls back to a default with only a log warning → the send fires at the **wrong local hour**, defeating the client's NOTE-47 timezone-fidelity requirement.

**(b) Plan as written.** Plan §4 item 11, the `timezone='EVENT'` resolution fallback chain: "`anchor.timezone` if the anchor model has a non-null timezone column (only `Shows` today, free-form `VarChar(50)` — validate against the IANA set; **invalid → default**) → else `schedule.timezone` IANA value if set → else system default new `ppl_settings schedule_default_timezone` (default `'America/New_York'` …), **log a warning**." The config-validation half of item 11 (reject `EVENT` where unresolvable; `EVENT` invalid for RECURRING) is correct and stands.

**(c) The delta.**

1. **Ingest-side validation (admin-backend-api).** Validate `Shows.timezone` to a canonical IANA zone **at write time**: in the show create/update DTO/service path, accept only values present in the runtime IANA set (`Intl.supportedValuesOf('timeZone')`, or equivalently a `date-fns-tz` resolvability check — the same library the worker uses, so the two ends cannot disagree). Reject invalid new writes with a 400. For **existing** rows (free-form legacy data): a one-time read-only audit (script or checklist query) that lists shows whose `timezone` does not parse, handed to whoever owns show data for correction — do not silently rewrite data.
2. **Send-side: fail closed, never guess** (amends the item-11 chain). The `EVENT` resolution chain becomes:
   `anchor.timezone` (must validate as IANA) → else `schedule.timezone` (IANA, if set) → else **occurrence `SKIPPED`, reason `"unresolvable event timezone"`, + a warn/alert log line** (same `ApplicationLogService` channel as the S3 sweep alert). **`schedule_default_timezone` is removed from the `EVENT` fallback chain entirely** — a not-sent, surfaced reminder is safer than a wrong-hour one. The knob itself may be retained only as an admin-UI authoring default (pre-filling the timezone field on a new rule); it must never be substituted at send time for an `EVENT` rule.
3. **Blast radius note:** the two in-scope Phase-3 anchors (`CART`, `PAYMENT_TRANSACTION`) have no timezone column, and item 11's config validation already forces them to carry an explicit IANA `schedule.timezone` — so `EVENT` resolution is effectively exercised only when the deferred `SHOW` anchor lands. Shipping fail-closed **now** means the behavior is already correct on the day show-relative scheduling arrives, at zero cost to Phase 3 traffic.
4. **Terminal-status reuse:** `SKIPPED` with a reason string is the established pattern (SMS gate, null recipient, missed window — plan §4 items 3/7/10); no new status or column is needed.

**(d) When:** **before Phase 3 ships** (review §5 step 1). The send-side fail-closed lands with the Phase 3 executor; the ingest validation can land any time before it, in admin-backend-api.

**(e) Open decision:** none.

---

## 7. S7 — PII in `recipients_snapshot`: closed by S1, tie the lifetime explicitly (Low)

**(a)** S7 / Low / `recipients_snapshot` stores recipient emails (PII) on every occurrence row with no retention tie-in.

**(b) Plan as written.** Plan §9 "FOLLOW_UP snapshot retention" flags it openly: "storing resolved recipients/replacements on the occurrence row … duplicates PII into the scheduling table; confirm acceptable vs storing only the domain anchor id." The scheduling register carries the same item as **SCH-3** (`EMAIL_SMS_SCHEDULING_KNOWN_ISSUES.md`, read-only for this track).

**(c) The delta.** No separate engineering. The review judges the snapshot **acceptable** (it is what enables the no-DRR ship path) and **properly bounded once S1 lands**. Apply two documentation bindings:

1. **Lifetime statement (record beside the S1 retention job):** *"`recipients_snapshot` lives exactly as long as its occurrence row: at most `schedule_occurrence_retention_days` (default 90) past terminal status. The snapshot exists solely to replay the dispatch verbatim (plan §2.2); after terminal status it has no consumer, so the retention purge is also the PII minimization mechanism."*
2. **Register note (for the user to apply — the register is read-only here):** SCH-3's PII half is bounded by the S1 retention window once built; its **staleness** half is answered by the combined-release D1 per-rule resolve-timing toggle (default = snapshot-at-materialize; freshness opt-in via `resolve_at_send` once DRR ships) — owned by the integration-spine doc, not this addendum.

**(d) When:** closed by S1 (before Phase 3 ships); the doc bindings land in the same PR as the retention job.

**(e) Open decision:** none.

---

## 8. X1 — Drop `CART_CONVERTED` from `NotificationStopCondition` until a distinct state exists (Low)

**(a)** X1 / Low / `CONTRACT_SIGNED` and `CART_CONVERTED` are aliases on today's schema (a cart converts to an `Order` on signature); shipping both enum values implies a capability that does not exist and invites a future author to pick `CART_CONVERTED` expecting different semantics.

**(b) Plan as written.** Plan §2.1 `stop_condition` row lists the set as "`CONTRACT_SIGNED`, `QUESTION_ANSWERED`, `CART_CONVERTED`, … `NONE`". Plan §4 item 4 specs the `CART_CONVERTED` resolver as literally "the **same** cart-signed check" and itself offers the alternative: "document … as aliases … **OR drop `CART_CONVERTED` until a distinct state exists**." Plan §9 repeats the choice. The review picks the plan's own alternative: drop it.

**(c) The delta.**

1. **Enum ships without it.** The Phase 1 migration creates `NotificationStopCondition` as `{ CONTRACT_SIGNED, QUESTION_ANSWERED, NONE }` — no `CART_CONVERTED` value in the Postgres enum or any of the five `schema.prisma` mirrors. No resolver, no DTO literal, no seed value references it.
2. **Everywhere the plan text mentions `CART_CONVERTED`** (§2.1, §4 item 4, §9; also the integration guide's illustrative examples and the register's SCH-4 row) — read it as removed for this build. The `CONTRACT_SIGNED` resolver spec (§4 item 4: parse `'cart:ID'`, resolved when `carts.status='signed'`) is unchanged and covers the real use case (the Store Contract Reminder, §4 item 8 mode (2)).
3. **Re-adding later is cheap and additive:** when a genuinely distinct converted-state exists in the domain model, `ALTER TYPE "NotificationStopCondition" ADD VALUE 'CART_CONVERTED'` (+ mirror + resolver + `IMPLEMENTED_STOP_RESOLVERS` entry) — no table rewrite, no occurrence impact. This keeps the stop-condition set honest without closing any door.
4. **Register note (user-applied):** SCH-4's planned-resolver list shrinks accordingly (`CONTRACT_SIGNED` / `QUESTION_ANSWERED` remain; `QUESTION_ANSWERED` stays `[dep]` per S4).

**(d) When:** the enum is created in Phase 1, so the *decision* applies at Phase 1; review sequencing files it under "during Phase 3/4" (step 2) because nothing consumes the enum until then. Net: build the Phase 1 migration without the value.

**(e) Open decision:** none — the review resolved the plan's own either/or.

---

## 9. X2 — Three new verification cases (Low)

**(a)** X2 / Low / The plan's §8 verification list is thorough but pre-dates these fixes; three cases must be appended so S1/S2/S6 are pinned by tests, not prose.

**(b) Plan as written.** Plan §8 already covers dedupe re-run, SENDING-reaper reset, catch-up skip, retry/backoff, DST gap, null-recipient guard, etc. It has **no** case for retention, for the documented reaper double-send behavior, or for bad-timezone fail-closed (its current timezone behavior is the §4 item 11 silent default that S6 removes).

**(c) The delta — append exactly three cases to the §8 list:**

1. **Retention (S1):** seed occurrences in every terminal status (`SENT`/`SKIPPED`/`CANCELLED`/`FAILED`) with `updated_at` older than `schedule_occurrence_retention_days`, plus PENDING/SENDING rows and *fresh* terminal rows; run the retention job; assert (i) only the stale terminal rows are deleted, (ii) deletion happened in batches of `schedule_retention_batch_size` (observe loop iterations or row counts per batch), (iii) PENDING/SENDING and fresh terminal rows are untouched, (iv) the protected latest-SENT row of a live FOLLOW_UP series survives (the §1(c)4 guard).
2. **Reaper double-send (S2):** force an occurrence into `SENDING` with `claimed_at` older than `schedule_sending_stale_minutes`; run a tick; assert it is reset to PENDING and re-dispatched. Assert the **documented at-least-once semantics**: the test's pass condition is "second dispatch occurs and is logged", with the accepted-duplicate behavior asserted against the written statement from §2(c)3 — and, *only if* ADD-Q1 later adopts provider idempotency, extend the test to assert the duplicate is suppressed at the provider boundary.
3. **Bad timezone (S6):** (i) ingest — `PUT`/`POST` a show with `timezone='EST5EDT-ish-garbage'` ⇒ 400, never persisted; (ii) send — an `EVENT`-timezone rule whose anchor carries an invalid/null zone and whose `schedule.timezone` is unset ⇒ the occurrence is `SKIPPED` reason `"unresolvable event timezone"` with a warn/alert log line, and **no** send is attempted at a defaulted zone.

**(d) When:** during Phase 3/4, in the same PRs as the behavior each case pins (retention test with S1, reaper test with the Phase 3 dispatch, timezone tests with S6).

**(e) Open decision:** none (case 2 has a conditional extension hanging off ADD-Q1).

---

## 10. D2 — Drop the `Exhibitor.company_id @unique` schema drift (Medium; standalone, decoupled from DRR)

**(a)** D2 / Medium / `Exhibitor.company_id` is declared `@unique` in the Prisma schemas while the real DB index is non-unique and multi-member companies are real — any Prisma query relying on one-exhibitor-per-company can silently regress (fetch-one where the DB has many). The review: "recommend formally dropping `@unique` from both schema files as a **standalone data-integrity fix, decoupled from DRR timing**, so it can't bite an unrelated query first."

**(b) Plan as written.** Not a plan section — the finding originates in the DRR gap analysis and the review routes it out of DRR into "decoupled, do soon" (review §5 step 3). It is included in this addendum because it is a five-schema data-integrity fix of exactly the kind this track's schema work touches, and because the review orders it done **now**, before any release-gated work depends on it.

**(c) The delta.**

1. **Correction to the review's scope — it is FIVE schema files, not two.** Verified by recon (2026-07-08): `company_id Int @unique @map("company_id")` on `model Exhibitor` exists in **all five** repos:
   - `admin-backend-api/prisma/schema.prisma:1030`
   - `exhibitor-backend-api/prisma/schema.prisma:1030`
   - `external-api-service/prisma/schema.prisma:1030`
   - `background-worker-service/prisma/schema.prisma:944`
   - `pulse-broker-service/prisma/schema.prisma:944`
   The review said "both schema files" because the DRR gap analysis examined the two it needed; the fix must land in all five or `db push` from an uncorrected sibling would try to re-impose the unique index.
2. **Schema edit (all five):** change

   ```prisma
   company_id             Int       @unique @map("company_id")
   ```
   to
   ```prisma
   company_id             Int       @map("company_id")
   ```
   and add `@@index([company_id])` to `model Exhibitor` so the (real, non-unique) index stays modelled and FK lookups stay indexed.
3. **Relation cardinality — the code-visible part.** Dropping `@unique` flips the Prisma relation from one-to-one to one-to-many: the `Company` back-relation `exhibitor Exhibitor?` (e.g. `admin-backend-api/prisma/schema.prisma:864`) must become `exhibitors Exhibitor[]` (rename per Prisma pluralization convention), in all five schemas. Every call site reading the singular relation then breaks **at compile time** (which is the point — the current code compiles while being wrong about the data). Recon sizing: **9** direct `company.exhibitor` / `company?.exhibitor` property accesses plus ~**16** `exhibitor:` include/select entries across the five `src/` trees (the broader `.exhibitor` grep hits ~743 lines, but almost all are *other* models' legitimately-singular exhibitor relations — e.g. `NotificationLog.exhibitor`, `ExhibitorAuditLog.exhibitor` — which are untouched). Each of the ~25 real sites needs an explicit one-vs-many decision (typically: iterate, or select the primary member by a documented rule) — never a silent `[0]`.
4. **Migration mechanics (admin owns it).** Because the drift means the *live DB* already has the non-unique index while the *schema* claims unique, first verify live state (`\d exhibitors` — confirm which index actually exists), then write the admin migration as hand-written **idempotent** SQL per house convention:

   ```sql
   -- align DB to the corrected schema; no-ops where the DB is already correct
   ALTER TABLE "exhibitors" DROP CONSTRAINT IF EXISTS "exhibitors_company_id_key";
   DROP INDEX IF EXISTS "exhibitors_company_id_key";
   CREATE INDEX IF NOT EXISTS "exhibitors_company_id_idx" ON "exhibitors"("company_id");
   ```

   Then mirror the schema edit to the four siblings and `db push` each (which, with the corrected schema, now converges instead of fighting the DB).
5. **Sequencing:** its own branch/PR, **not** bundled into any scheduling phase — "decoupled, do soon" (review §5 step 3). It unblocks nothing in Phases 1–5 and must not gate them; conversely no scheduling code may be written that assumes one exhibitor per company (the scheduling plan does not — its recipient sources are anchor-row columns, never a `company.exhibitor` hop).

**(d) When:** **decoupled — do soon**, independent of the phasing; before any new code (DRR included) queries `Exhibitor` by `company_id` expecting uniqueness.

**(e) Open decision:** none from the review. (The per-call-site one-vs-many resolutions in (c)3 are ordinary code review, handled in that PR.)

---

## 11. Addendum question register (all ADD-Qn)

| ID | Maps to | Question | Default if unanswered |
|---|---|---|---|
| **ADD-Q1** | S2 | Accept **at-least-once** with the reaper tail-risk, or design provider-side idempotency (SendGrid idempotency / `NotificationLog` pre-insert keyed on `dedupe_key`) in now? | Accept at-least-once; state it explicitly (§2(c)3). |
| **ADD-Q2** | S3 | Catch-up model: (A) single default `SKIP` + per-rule `catchup_policy` override, or (B) additionally per-kind DTO defaults (proximity → SKIP, follow-up/payment → SEND)? | (A). |
| **ADD-Q3** | S4 | Defer the "unanswered product questions" RECURRING template with the show/workshop anchors (option (a)), or must it ship this build (option (b): model the answer table + specify the instance-discovery query)? | (a) defer. |

D1's resolve-timing question and D3's zero-recipient policy are **not** duplicated here — they live with the DRR plan / integration-spine doc (§0.2).

---

## 12. Consolidated new-surface summary (for the implementer's checklist)

**New `ppl_settings` keys (this addendum):** `schedule_occurrence_retention_days` (90, clamp [7,365]) · `schedule_retention_batch_size` (5000, clamp [500,20000]) · `schedule_retention_max_batches_per_run` (20, clamp [1,100]). **Changed knob semantics:** `schedule_default_timezone` is removed from the `EVENT` send-time fallback chain (S6) — authoring default only. All other plan §6 knobs unchanged.

**Schema deltas (admin migration + 4× mirror + `db push`):** `notification_schedules.catchup_policy` enum NOT NULL default `SKIP` (S3) · `NotificationStopCondition` ships **without** `CART_CONVERTED` (X1) · `Exhibitor.company_id` loses `@unique`, gains `@@index`, `Company` back-relation goes plural — five schemas, standalone PR (D2). No `NotificationLog` changes here (that is the spine doc's unified migration, M3).

**New worker code:** retention cron (Registrar/Task/Service triple + SQS allow-list entry) with the FOLLOW_UP latest-row guard (S1) · `FOR UPDATE SKIP LOCKED` claim transaction (S2) · per-rule catch-up branch + per-skip and aggregate alert lines (S3) · fail-closed `EVENT` timezone resolution → `SKIPPED "unresolvable event timezone"` (S6).

**New admin code:** IANA validation on `Shows.timezone` writes + legacy-rows audit query (S6) · `catchup_policy` on `ScheduleRuleDto` + audit (S3).

**Tests:** DST fall-back ambiguous-hour test (S5) + the three §8 additions: retention / reaper-double-send / bad-timezone (X2).

**Deferred by decision:** "unanswered product questions" RECURRING template (S4, pending ADD-Q3) · provider-side send dedupe (S2, pending ADD-Q1).

*Per project convention: no commits are made by this track; the user reviews and commits every repo. The base plan file, the story, and both known-issues registers remain unedited — register updates suggested above (§7, §8) are proposals for the user to apply.*
