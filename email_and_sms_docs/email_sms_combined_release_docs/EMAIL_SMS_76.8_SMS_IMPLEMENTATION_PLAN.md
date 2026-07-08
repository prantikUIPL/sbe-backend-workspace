---
atom_id: EMS-768-SMS
title: SMS Provider Integration (Twilio Programmable Messaging) — story 76.8
version: v1
status: draft
type: implementation
sessions: 1
session: 1
epic: "Email & SMS Management (SBE-671) — combined release"
estimate: 73.0h
risk_tier: high
priority: Must Have
depends_on: [EMS-766-SCHED, EMS-779-DRR]
blocks: []
tags: [email-sms, sms, twilio, notifications, combined-release, compliance, tcpa, 10dlc]
plan_family: null
parent_plan: null
covers_atoms: null
regulated_workload: false
compliance_scope: null
---

# EMS-768-SMS Implementation Plan — SMS Provider Integration (Twilio Programmable Messaging) (v1 — Draft)

**Scope:** 1 session (single plan, phased build). Part of the **combined release**: Scheduling (76.6/77.8) + DRR (77.9) + SMS (76.8) ship together on the shared spine — **one recipient-resolution engine, ONE unified `NotificationLog` migration, the D1 per-rule resolve-timing toggle (default = snapshot-at-materialize)**.

**Source:** `EMAIL_SMS_76.8_SMS_REFINED_STORY.md` (FR-1…FR-17, AC-1…AC-26, un-gating checklist §9) → EMS-768-SMS.

**Canon reconciliation:** The client named the provider "SendGrid", but SendGrid's API is email-only — it has no SMS send endpoint. This plan builds against **Twilio Programmable Messaging** (same vendor family; Twilio owns SendGrid) as the PROPOSED default per refined story §4.1, **gated on SMS-01 client confirmation — never silently assumed**. `EMAIL_SMS_KNOWN_ISSUES.md` #2 records 76.8 as deferred (2026-06-03 verbal BA agreement); the combined release pulls it forward — that reversal is **SMS-02**, the meta-gate on every step below. Register wording fix M1 ("SMS create is gated; storage shape undefined", not "already built") remains a user action — the register file is frozen to this pipeline.

---

## Gate Contract

Ordered by criticality. All are binary and externally verifiable.

- [ ] **Day-one long pole started:** SMS-01/SMS-02 question pack sent to client/BA and Twilio account + A2P 10DLC brand/campaign registration kicked off on confirmation (registration takes days-to-weeks and runs in parallel with all build phases — refined story §4.2).
- [ ] Worker boots with valid `TWILIO_*` creds and initializes the SMS sender; with creds absent it logs + skips ("not configured" mode), never throws (AC-1).
- [ ] Predefined template create with `channel='SMS'` passes DTO+service validation; custom SMS create still rejected (AC-3).
- [ ] A due `channel='SMS'` occurrence (post-flip, all pre-send checks green) dispatches via the same by-id `notificationTemplateId` path as email, writes a `NotificationLog` row with `channel='SMS'`, E.164 destination in the generalized recipient column, `provider='twilio'`, Message SID in `provider_message_id`, PENDING-first (AC-17, AC-21).
- [ ] Pre-flip behavior preserved: `channel='SMS'` occurrences materialize then SKIP with reason `"SMS provider not integrated"` until the un-gating checklist (refined story §9) is fully green, in order (AC-22, AC-24).
- [ ] Suppressed number ⇒ no provider call, outcome logged suppressed; STOP webhook or manual opt-out adds the number to the suppression store effective next dispatch (AC-12, AC-13).
- [ ] Scheduled SMS inside a state-aware quiet window is deferred to the next allowed window, not dropped and not sent in-window (AC-14).
- [ ] `sms_sending_enabled` off (default) ⇒ zero live SMS in any environment; dispatches log skipped-by-config. **No production SMS before 10DLC brand + campaign are registered and the Messaging Service/number is provisioned** (AC-16).
- [ ] Twilio status callback with valid `X-Twilio-Signature` updates the matching log row by `provider_message_id`, is idempotent on replay; invalid signature rejected (AC-19).
- [ ] Reaper-induced re-dispatch of an SMS occurrence does not double-text (dedupe keyed on occurrence `dedupe_key`, AC-23).
- [ ] Email regression: every pre-existing log row reads `channel='EMAIL'` after the unified migration; email dispatch, logging, and the payment-reminder dedupe query behave unchanged (AC-18).
- [ ] All quality gates green (lint/typecheck/test/SonarQube ×5 repos).

**Atom-level acceptance criteria:** the refined story's AC-1…AC-26 are the atom acceptance set; this plan's tests map to them (see Tests). The gate flip itself is executed only per the §9 un-gating checklist.

---

## Context

**Why:** The combined release ships scheduling with a deliberately pre-built SMS gate: occurrences materialize then SKIP with `"SMS provider not integrated"` (scheduling plan §4 item 10; scheduling story AC-15/16). Without 76.8, every SMS-channel send in the client's template list — including the two client-cited scheduled SMS (Workshop Confirmation −24h, product-question SMS) — stays permanently SKIPPED, SMS templates cannot even exist (create is hard-blocked at `SUPPORTED_TEMPLATE_CHANNELS = ['EMAIL']`, `admin-backend-api/src/admin/notification-template/dto/notification-template.dto.ts:27`), and the audit surface cannot record an SMS destination (`NotificationLog` has no channel column and a single `email String?` recipient, `admin-backend-api/prisma/schema.prisma:309-335`). Since Feb 2025, US carriers **block** 100% of unregistered 10DLC traffic — so the provisioning long pole (Twilio account + A2P 10DLC brand/campaign) blocks production launch and must start day one, regardless of build speed.

**What:** An `SmsService` in `background-worker-service` (sibling to `src/notification/mailer.service.ts`, same never-throws / PENDING-first contract) sending via Twilio Programmable Messaging through a single global Messaging Service SID; SMS template existence unlocked (channel gate widened, `SmsChannelConfigDto` defined, predefined SMS rows seeded per the confirmed trigger list); recipient phones resolved by the **shared recipient-resolution engine** (DRR's, extended to a phone field — never a parallel resolver, M4 sequencing); a platform-controlled suppression store + state-aware quiet-hours + consent-event records (compliance substrate); a Twilio status-callback webhook in `external-api-service` (third instance of the Stripe/Nunify recipe); and the mechanical scheduling un-gate flip (remove the SMS-SKIP pass, widen the dispatch select, extend the by-id channel assertion).

### Reference Documents

| Document | Type | Refer To | Purpose |
|----------|------|----------|---------|
| `email_sms_combined_release_docs/EMAIL_SMS_76.8_SMS_REFINED_STORY.md` | Spec | Full document (FR-1…FR-17, §4, §9, §12) | Requirement baseline; question IDs (SMS-01…SMS-15, SMS-S1/S2); un-gating checklist |
| `email_sms_scheduling_plan_and_supporting_docs/EMAIL_SMS_SCHEDULING_IMPLEMENTATION_PLAN.md` | Dependency plan (READ-ONLY) | §2.2 (occurrence table), §4 items 3/9/10 (dispatch, by-id, SMS gate), §7 phase 6 (gate flip), §6 (ppl_settings) | The scheduler contract this plan plugs into — inherited unchanged, not restated |
| `email_sms_combined_release_docs/EMAIL_SMS_77.9_DRR_REFINED_STORY.md` | Dependency spec | FR-18/FR-20/FR-21, §6.2, DRR-S2 | Owns the shared engine (phone-extensible interface) and authors the ONE unified `NotificationLog` migration this plan consumes |
| `EMAIL_SMS_76.8_SMS_PROVIDER_INTEGRATION_GAP_ANALYSIS.md` | Spec | SMS-01…SMS-15 registers | Full question text + file:line evidence behind each BLOCKED-ON row |
| `scratchpad/research_sms_codebase.md` | Pattern reference | §1–§5 | Codebase reality with file:line citations (mailer contract, channel gate, log shape, phone data, webhook recipe) |
| `scratchpad/research_scheduling_contract.md` | Dependency contract | §(b)–§(e), summary | Materialize-then-SKIP gates, occurrence state machine, by-id dispatch, D1/S1/S2 findings as they bind SMS |
| `background-worker-service/src/notification/mailer.service.ts` | Pattern reference | Lines 69-81 (not-configured), 95-101 (slug lookup), 125-183 (PENDING-first log) | The contract `SmsService` mirrors |
| `external-api-service/src/modules/webhook/controllers/webhook.controller.ts` | Pattern reference | Lines 36-56 | Stripe recipe the Twilio webhook copies: `@Public()` → signature verify (rawBody) → idempotency row → Mongo archive → typed handling |
| `background-worker-service/src/common/ppl-settings/ppl-settings.service.ts` | Pattern reference | Lines 13-60 | Tunables pattern: typed getters, 60s TTL cache, SQS-triggered `invalidate()` |
| `exhibitor-backend-api/src/common/helpers/validators/is-valid-phone.validator.ts` | Pattern reference | Line 16 (`PHONE_DIGITS_REGEX`) | Stored phone format (digits-only 10–15, no `+`) the normalizer must handle |
| `admin-backend-api/src/database/seeds/notification-template.seeder.ts` | Pattern reference | Full file | Seeder pattern for the SMS predefined rows (29 EMAIL rows today, zero SMS) |

**Dependencies (blocking):**
- **EMS-766-SCHED (scheduling build)** — delivers the occurrence pipeline, the `channel='SMS'` SKIP pass, the by-id `notificationTemplateId` dispatch path, `recipients_snapshot`, retry taxonomy, S1 retention, S2 at-least-once claim. Status: approved plan (Revision 3), build sequenced first in the combined release.
- **EMS-779-DRR (DRR build)** — delivers the generalized shared resolver (phone-extensible interface, DRR FR-21) and **authors the ONE unified `NotificationLog` migration** (channel + generalized recipient + DRR-S2 legacy-email preservation). M4 sequencing is binding: **email DRR ships first; SMS extends that same resolver** — no SMS work stands up a resolver of its own.
- **Client/BA answers** — SMS-02 (scope reversal), SMS-01 (mechanism + account ownership), SMS-08 (10DLC registration owner), SMS-03 (consent policy), SMS-06/07 (trigger list + per-trigger phone mapping). See BLOCKED-ON.

**Scope boundary:** This plan owns the SMS transport, template unlock, compliance substrate, webhook, and the gate flip. It does **not** own: the unified `NotificationLog` migration DDL (DRR track authors it; this plan specs the SMS-side requirements and consumes it via `db push`), the shared resolver internals (DRR track; this plan adds phone columns to the per-anchor allow-list and consumes the engine), the scheduler state machine (inherited unchanged), the #21 slug-path fix (ships with the scheduling build; the by-id path SMS joins is immune by construction), or the deferred event/workshop anchors the two client-cited SMS templates additionally need (scheduling track's deferred scope, P9-2).

**Explicit implementation dependency:** SMS dispatch is structurally complete once Phases C–H land, but **not effective in production** until the external provisioning completes: Twilio account + A2P 10DLC brand/campaign registered + Messaging Service/number provisioned (§4.2, AC-16). Until then everything runs against Twilio test credentials with `sms_sending_enabled=false`. This is acknowledged: the code ships dark behind the kill switch; provisioning is the launch gate, not a build gate.

---

## Design Decisions

Numbered DD-1… to avoid colliding with the external-review finding IDs (S1–S7/D1–D3/M1–M4/X1–X2), which this plan cites by their original names.

### DD-1: Provider mechanism = Twilio Programmable Messaging (PROPOSED — SMS-01); build proceeds dark, provisioning waits

SendGrid's API cannot send SMS; Twilio Programmable Messaging is the only feasible in-family mechanism (refined story §4.1). No Twilio reference exists in any of the five repos today (grep `twilio|nexmo|vonage|plivo` = zero; research §1.1). **Implication:** code build proceeds on the Twilio default immediately (SDK, service, webhook — all inert behind the kill switch and "not configured" mode), but **no account creation, number purchase, or registration happens before SMS-01 is confirmed**. Putting SMS-01 to the client is the day-one action of the release; registration starts the moment it is confirmed and runs in parallel with everything else. If SMS-01 comes back with a different mechanism, Phases A/E/G re-plan (`PLAN_BLOCKED`) — nothing else changes.

### DD-2: Credentials = env + AWS Secrets; tunables = `ppl_settings`; no DB creds, no config UI

Mirrors the SendGrid precedent exactly (`SENDGRID_API_KEY`/`SENDGRID_FROM` via per-repo `.env` + `loadAwsSecrets()` before `ConfigModule` — `background-worker-service/src/config/env.validation.ts:28-29`). New keys: `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_MESSAGING_SERVICE_SID` (worker; `TWILIO_AUTH_TOKEN` also in external-api-service for signature validation). **Joi validation marks them `optional()`** — unlike the required SendGrid keys — so environments without SMS keep booting; absent creds put `SmsService` in "not configured" mode (log + skip, never throw; mailer precedent `mailer.service.ts:69-81`). Behavioral tunables (`sms_sending_enabled`, quiet-hours windows, segment cap) are `ppl_settings` rows read through `PplSettingsService` (60s TTL + SQS `invalidate()`); SMS adds its **own** keys and never repurposes the `schedule_*` knobs (refined story FR-2). No admin provider-config screen this release (SMS-04 PROPOSED).

### DD-3: One shared recipient engine, extended to a phone field — never a parallel resolver (M4)

Binding sequencing per the release spine: (1) email DRR generalizes the scheduler's restricted `recipient_source`/`replacements_map` resolver; (2) SMS reuses that same engine extended to a phone field. Concretely this plan's only resolver work is: add **phone columns** to the per-anchor allow-list (e.g. `Exhibitor.phone` — `String @db.VarChar(20)` NOT NULL, `admin-backend-api/prisma/schema.prisma:1029`) and pass a destination-field parameter through DRR's phone-extensible interface (DRR FR-21). Both validation points (config-time AND materialize-time) apply unchanged. **Do NOT** write any SMS-specific lookup, do NOT touch the ad-hoc per-flow recipient code (`lead-notification.service.ts` etc.), do NOT loosen `RecipientList`'s `IsEmail` yourself — the typed-entry structure is DRR's (DRR FR-5). Zero-recipient policy inherits D3: skip-and-log marketing/reminder, abort-and-alert transactional, never send to zero.

### DD-4: The unified `NotificationLog` migration is spine-owned; SMS states requirements, does not author DDL

ONE migration, authored on the DRR track (DRR FR-18/§6.2), admin-backend-api owns it, the other four repos take it via `db push` (CLAUDE.md). Sequenced per M3: immediately after the SMS-02 scope decision, **before any SMS send code merges**. SMS-side requirements on that migration (consumed here, verified in Phase 0/B): (a) `channel NotificationChannel NOT NULL` backfilled `'EMAIL'`; (b) the generalized recipient representation records an E.164 SMS destination; (c) the legacy `email` column stays populated (DRR-S2 — protects the payment-reminder dedupe query); (d) no new BigInt PKs (`NotificationLog.id` BigInt is the pre-existing approved exception). **Delivery-status values need no schema change:** `NotificationLog.status` is `String @db.VarChar(50)` (not an enum, `schema.prisma` line in §3 of research doc), so the callback can write `'DELIVERED'` without touching the migration — this plan adopts `PENDING → SENT → DELIVERED | FAILED` as string values for SMS rows.

### DD-5: `SmsService` mirrors the worker `MailerService` contract exactly

Same shape, native implementation (cross-repo house rule; the four mailer copies are the precedent): returns `{ status: 'SENT'|'FAILED'|'SKIPPED', providerMessageId?, error?, skipReason? }`, **never throws**, writes the `NotificationLog` row `PENDING`-first then updates (crash-safe; `mailer.service.ts:125-183` precedent), records `provider: 'twilio'` + Message SID in `provider_message_id` (the join key the webhook needs). **Dispatch reads `channel_config`** — SMS does not clone the email path's ignore-config-at-dispatch gap (that email-side gap stays flagged for the register, not fixed here). Only the worker gets an `SmsService` this release: both known SMS templates are scheduled sends and the launch scope has no confirmed immediate trigger (SMS-06 OPEN); admin/exhibitor get native equivalents only if SMS-06 confirms an immediate trigger living there.

### DD-6: Plain-text rendering, 3-segment hard cap, warn-at-1 (PROPOSED — SMS-10)

SMS bodies render as plain text: literal `{{token}}` split/join substitution (same raw, un-escaped semantics as email plaintext), no subject, no HTML escaping, no `renderWithLayout` shell, no asset URLs. **Constants:** `SMS_GSM7_SINGLE = 160`, `SMS_GSM7_CONCAT = 153`, `SMS_UCS2_SINGLE = 70`, `SMS_UCS2_CONCAT = 67`, `SMS_MAX_SEGMENTS = 3` (≈459 GSM-7 chars). Save-time template validation computes worst-case segment cost and **warns** above one segment (metadata in the response, not a rejection); dispatch-time the **resolved** body over `SMS_MAX_SEGMENTS` is a **hard failure** (log `FAILED`, no retry, no truncation). Unicode allowed; validator surfaces the UCS-2 cost.

### DD-7: E.164 normalization is a dispatch-time pure function; skip + log fallback (PROPOSED — SMS-11, SMS-12)

Stored numbers are digits-only 10–15 chars without `+` (`PHONE_DIGITS_REGEX`, `is-valid-phone.validator.ts:16`), fail-open validated, with known malformed rows. `normalizeToE164(raw)`: strip non-digits; 10 digits → `+1` + digits; 11 digits leading `1` → `+` + digits; anything else → `null`. US/CA-only launch (FR-16); non-normalizable ⇒ **skip + log** — occurrence `SKIPPED` reason `"invalid or missing phone number"` (joins the scheduler's existing SKIP-reason vocabulary) on the scheduled path; never a default number, never aborting sibling recipients; transactional triggers escalate per D3. `validatePhoneDeep` is NOT called on the send path (capture-time concern, out of scope).

### DD-8: Platform-controlled suppression store is authoritative (PROPOSED — SMS-03/M2); needed under every consent answer

A new admin-owned table `sms_suppressions` keyed by E.164 number records opt-outs from **any reasonable method** (provider STOP webhooks AND manually registered requests). Every SMS dispatch checks it pre-send; suppressed ⇒ skip + log outcome `suppressed`. Twilio account-level STOP handling stays on as defense-in-depth; the platform store is authoritative. Consent-grant/revocation events land in append-only `sms_consent_events` (≥5-year retention — no purge job touches it). The consent *policy* (which entity holds consent, prior-express-consent requirement) is OPEN (SMS-03) — the tables are buildable now because they are required under every answer; only the capture flow that writes GRANT rows waits on SMS-03.

### DD-9: State-aware quiet hours, data-driven, deferral not drop (PROPOSED — M2); scheduled path only at launch

Windows held as `ppl_settings` data (updatable without redeploy): `sms_quiet_hours_default` (`"08:00-21:00"` — TCPA baseline) + `sms_quiet_hours_overrides` (JSON keyed by state: FL/OK/WA `"08:00-20:00"`; TX `"09:00-21:00"` Mon–Sat / `"12:00-21:00"` Sun). Destination state derived from the NANP area code via a code-constant map (best available signal for a phone-only destination; documented approximation). Enforcement point: the SMS pre-send pipeline in the dispatcher — an in-window violation **defers**: the occurrence stays `PENDING` with `next_attempt_at = next allowed window start`, **without incrementing `attempt_count`** (a deferral is not a retry; the scheduler recomputes `fire_at` only for PENDING per its own AC — this uses the retry bookkeeping columns, not `fire_at`). **Immediate/transactional SMS quiet-hours behavior is OPEN (SMS-S1)** — safe because launch scope contains no immediate SMS trigger (DD-5); the enforcement point is built where both paths converge so answering SMS-S1 is config, not rework.

### DD-10: Duplicate-text protection under at-least-once (S2) — dedupe keyed on occurrence `dedupe_key`

The scheduler is explicitly at-least-once (SENDING-reaper reset can re-dispatch). A duplicate SMS is costlier than a duplicate email (compliance + annoyance + spend), so SMS dispatch layers two guards keyed on the occurrence `dedupe_key`: **(1) platform-side short-circuit** — before the provider call, if a `NotificationLog` row already exists for this occurrence (`occurrence.notification_log_id` set) with a `provider_message_id`, treat as sent and finalize without re-sending; **(2) provider-side idempotency** — pass the `dedupe_key`-derived token through Twilio's request-idempotency mechanism. The exact Twilio idempotency capability is **verified during Phase A R&D** (do not assume the header/param name from memory); if the provider offers none, guard (1) plus the claim/`FOR UPDATE SKIP LOCKED` semantics are the accepted residual, matching the scheduler's stated at-least-once tail risk. Immediate (non-scheduled) sends are single-attempt (no email-layer retry exists anywhere; `NotificationLog.retry_count` stays dormant).

### DD-11: Twilio error codes classify into the scheduler's existing transient/hard retry taxonomy — no new state machine

Transient (provider 5xx, timeouts, rate/queue errors) → occurrence back to `PENDING` with backoff `[5m, 30m, 2h]`, `MAX_OCCURRENCE_ATTEMPTS = 3`. Hard (invalid/unreachable number, suppressed recipient, auth/4xx, over-cap body, unregistered-traffic blocks) → `FAILED`/`SKIPPED` immediately, no retry (scheduling plan §4 item 3, inherited unchanged). The classification lives in one function (`classifyTwilioError`), unit-tested per representative error-code class.

### DD-12: Status callback = third instance of the established webhook recipe

New public POST endpoint in `external-api-service` (the inbound-webhook host): `@Public()` route → `X-Twilio-Signature` verification against the exact raw body (app already boots `rawBody: true`, `external-api-service/src/main.ts:9`) → DB idempotency row in new admin-owned table `twilio_webhook_events` (unique on `(message_sid, message_status)`) → Mongo archive (365-day TTL, mirroring the Stripe/Nunify archive services) → typed handling: match `NotificationLog` on `provider_message_id`, map `delivered → 'DELIVERED'`, `undelivered/failed → 'FAILED'` + Twilio error code into `error`. Replayed callbacks are idempotent (unique-row insert short-circuits). Out-of-order callbacks: a terminal `'FAILED'`/`'DELIVERED'` is never downgraded to `'SENT'`.

### DD-13: Gate-flip mechanics (FR-13) — mechanical, zero scheduling-schema change, no re-materialization

Three code moves, in one PR, executed only when the §9 un-gating checklist is green: (1) remove the SMS-SKIP pass (the pass that flips `channel='SMS'` PENDING rows to `SKIPPED "SMS provider not integrated"`, scheduling plan §4 item 10); (2) widen the dispatch select from `channel='EMAIL'` to both channel values; (3) extend the by-id dispatch channel assertion — the function family that asserts `channel==='EMAIL' && is_active` gains the `channel==='SMS'` branch routing to `SmsService` — **same by-id path, same NotificationLog write, not a forked sender** (inherits #21 immunity by construction). A new pre-send check joins the pipeline: `sms_sending_enabled` off ⇒ occurrence `SKIPPED` reason `"sms sending disabled by config"` (new entry in the shared SKIP-reason vocabulary) — this is also the rollback lever. `recipients_snapshot` generalizes to carry a phone destination without breaking the email fields (`to[]/cc[]/bcc[]/replacements/from_name/reply_to` keep flowing to `sgMail.send`).

### DD-14: Custom SMS templates stay blocked; predefined-only unlock (FR-3)

`SUPPORTED_TEMPLATE_CHANNELS` widens to `['EMAIL', 'SMS']` (the deliberate one-place change, `notification-template.service.ts:226-228` comment), but the service invariant adds: `channel==='SMS' && !is_predefined` ⇒ reject `'Custom templates support EMAIL channel only'`. Predefined SMS rows honor the existing dormant guard (`notification-template.service.ts:408-416`): `subject` stays null/non-editable, `channel_config` system-controlled — same tiering philosophy as `PREDEFINED_EDITABLE_CONFIG_KEYS`. Seeding follows the template-ownership rule: this story seeds its own slugs/templates, one per confirmed SMS-06 trigger.

### DD-15: Sender identity = one global Messaging Service; no per-template sender, no SMS whitelist table (PROPOSED — SMS-08)

All egress addresses a single `TWILIO_MESSAGING_SERVICE_SID` pooling 10DLC-registered number(s). No `sender_id` key in `SmsChannelConfigDto` this release (added later only if SMS-08 lands on per-template senders); no `AllowedFromDomain` analogue (sender is a system identity, not admin-selectable). The Messaging Service also provides provider-side queuing/pacing against A2P MPS caps — no platform-side rate governor this release (FR-14; the bulk-trigger question stays OPEN with SMS-06/SMS-14).

### DD-16: Concurrency hazard analysis

- New paths running concurrently against the same resource? **Yes** — the widened dispatch select claims SMS occurrences under the same `FOR UPDATE SKIP LOCKED` claim + SENDING-reaper machinery as email (inherited unchanged, no new claim logic); the webhook handler updates `NotificationLog` rows concurrently with dispatcher writes. *Mitigation:* claim semantics inherited from the scheduler (S2); webhook updates are row-targeted by `provider_message_id` with terminal-status monotonicity (DD-12) and idempotency rows.
- Tighter loop / higher emission rate? **No** — same heartbeat tick, same `MAX_DISPATCH_PER_RUN` budget now shared across both channels.
- New automatically-triggered action? **Yes** — the quiet-hours deferral re-schedules occurrences. *Mitigation:* deferral sets `next_attempt_at` without touching `attempt_count`; bounded by the window math (next allowed start), cannot loop within a window.
- Changes any concurrency-control constant? **No** — backoff `[5m,30m,2h]`, attempts 3, reaper window, batch caps all inherited.

---

## Files

Grouped by repo. Admin owns all migrations; exhibitor/external/worker/pulse mirror schema via `db push`. All new PKs are `Int`; new columns NOT NULL + backfill wherever a default exists.

### admin-backend-api

| File | Action | Description |
|------|--------|-------------|
| `src/admin/notification-template/dto/notification-template.dto.ts` | MODIFY | Widen `SUPPORTED_TEMPLATE_CHANNELS` (line 27); add `SmsChannelConfigDto`; wire channel-conditional `channel_config` validation |
| `src/admin/notification-template/notification-template.service.ts` | MODIFY | SMS branch: custom-SMS reject (beside :229-231), SMS config normalization, segment-cost warning at save, honor dormant guard (:408-416) |
| `prisma/schema.prisma` | MODIFY | `SmsSuppression`, `SmsConsentEvent`, `TwilioWebhookEvent` models (unified `NotificationLog` change lands via the DRR-track migration — not authored here) |
| `prisma/migrations/{ts}_sms_compliance_and_webhook_tables/migration.sql` | CREATE | Suppression + consent + webhook-idempotency tables (Step D1) |
| `src/database/seeds/notification-template.seeder.ts` | MODIFY | `SMS_PREDEFINED_TEMPLATES` block — one row per confirmed SMS-06 trigger (scaffold ships with an empty list until SMS-06 lands) |
| `src/database/seeds/ppl_settings.seeder.ts` | MODIFY | `sms_sending_enabled`, `sms_quiet_hours_default`, `sms_quiet_hours_overrides`, `sms_max_segments` keys |

### background-worker-service

| File | Action | Description |
|------|--------|-------------|
| `package.json` | MODIFY | `twilio` SDK dependency |
| `src/config/env.validation.ts` | MODIFY | `TWILIO_ACCOUNT_SID` / `TWILIO_AUTH_TOKEN` / `TWILIO_MESSAGING_SERVICE_SID` — Joi `.optional()` (DD-2) |
| `src/notification/sms.service.ts` | CREATE | `SmsService` (DD-5): Twilio client init / not-configured mode, PENDING-first log, dedupe guard, `classifyTwilioError` |
| `src/notification/sms-render.util.ts` | CREATE | Plain-text token substitution + GSM-7/UCS-2 segment calculator + cap check (DD-6 constants) |
| `src/notification/sms-phone.util.ts` | CREATE | `normalizeToE164` pure function + NANP area-code→state map (DD-7/DD-9) |
| `src/notification/sms-compliance.service.ts` | CREATE | Suppression pre-send check; quiet-hours window math + deferral decision (DD-8/DD-9) |
| `src/notification/notification.module.ts` | MODIFY | Register the three new providers |
| *(scheduling-build dispatcher module — exact path per the scheduling build, verify Phase 0; scheduling plan §4 items 3/9/10)* | MODIFY | Gate flip: remove SMS-SKIP pass, widen dispatch select, `channel==='SMS'` by-id branch → `SmsService`, pre-send pipeline (kill switch → resolve → normalize → suppression → quiet hours → segment cap) |
| `prisma/schema.prisma` | MODIFY | `db push` mirror of the new models + unified NotificationLog shape |

### external-api-service

| File | Action | Description |
|------|--------|-------------|
| `src/modules/webhook/controllers/twilio-webhook.controller.ts` | CREATE | `@Public() @Post('webhook/twilio/sms-status')` + `X-Twilio-Signature` verification (rawBody already on, `src/main.ts:9`) |
| `src/modules/webhook/services/twilio-webhook.service.ts` | CREATE | Idempotency row insert, log-row update by `provider_message_id`, terminal-status monotonicity (DD-12) |
| `src/modules/webhook/services/twilio-webhook-archive.service.ts` | CREATE | Mongo archive, 365-day TTL (Nunify archive pattern) |
| `src/config/…env validation` | MODIFY | `TWILIO_AUTH_TOKEN` (signature validation only), Joi `.optional()` |
| `prisma/schema.prisma` | MODIFY | `db push` mirror |

### exhibitor-backend-api / pulse-broker-service

| File | Action | Description |
|------|--------|-------------|
| `prisma/schema.prisma` (both repos) | MODIFY | `db push` schema mirror only — no SMS code this release (DD-5) |

### Tests

| File | Action | Description |
|------|--------|-------------|
| `admin-backend-api/src/admin/notification-template/…spec.ts` (existing suites) | MODIFY | Channel-gate widen, `SmsChannelConfigDto`, custom-SMS reject, guard honor, seeder |
| `background-worker-service/src/notification/sms.service.spec.ts` | CREATE | Transport, not-configured, log ordering, dedupe, error classification |
| `background-worker-service/src/notification/sms-render.util.spec.ts` | CREATE | Rendering + segmentation |
| `background-worker-service/src/notification/sms-phone.util.spec.ts` | CREATE | E.164 normalization + area-code state map |
| `background-worker-service/src/notification/sms-compliance.service.spec.ts` | CREATE | Suppression + quiet-hours (compliance cases) |
| `background-worker-service/…dispatcher spec (scheduling-build suite)` | MODIFY | Gate flip, pre-send pipeline order, pre-flip SKIP preserved, email regression |
| `external-api-service/src/modules/webhook/…twilio-webhook.spec.ts` | CREATE | Signature, idempotency, status mapping, monotonicity |

---

## Public API Contract

### Caller Contract — `SmsService` (worker)

The scheduling dispatcher is the only production caller this release. It must run the pre-send pipeline (kill switch → resolve → normalize → suppression → quiet hours → segment cap) **before** calling send; `SmsService.sendSms` re-checks nothing schedule-shaped (occurrence state is the dispatcher's job) but independently enforces not-configured mode and the dedupe guard. `SmsService` never throws.

### Exported Symbols

- `SmsService`
  - `sendSms(opts: { toE164: string; body: string; notificationTemplateId: number; exhibitorId?: number; userId?: number; dedupeKey?: string }) -> Promise<{ status: 'SENT'|'FAILED'|'SKIPPED'; providerMessageId?: string; error?: string; skipReason?: string }>` — PENDING-first log write; `provider: 'twilio'`; Message SID captured; dedupe short-circuit on `dedupeKey` (DD-10)
  - `isConfigured(): boolean`
- `sms-render.util`
  - `renderSmsBody(template: string, replacements: Record<string, string>) -> string` — raw `{{token}}` substitution, no escaping
  - `computeSegments(body: string) -> { encoding: 'GSM7'|'UCS2'; segments: number; chars: number }`
- `sms-phone.util`
  - `normalizeToE164(raw: string | null | undefined) -> string | null` — US/CA rules only (DD-7)
  - `stateForE164(e164: string) -> string | null` — NANP area-code map (DD-9)
- `SmsComplianceService`
  - `isSuppressed(toE164: string) -> Promise<boolean>`
  - `quietHoursDeferral(toE164: string, now: Date) -> Promise<Date | null>` — `null` = sendable now; a Date = next allowed window start

### Consumer Responsibilities

- Dispatcher passes the occurrence `dedupe_key` on every scheduled send (AC-23 depends on it).
- Dispatcher maps `SKIPPED` results to the shared SKIP-reason vocabulary; `FAILED` results through `classifyTwilioError` into the inherited retry taxonomy (DD-11).
- Nobody calls Twilio outside `SmsService`; nobody resolves phone recipients outside the shared engine (DD-3).

---

## Substrate Verification (Phase 0)

Run before any implementation step. Halt with `PLAN_BLOCKED` on mismatch — do not improvise.

| # | Check | Command / inspection | Expected | If mismatch |
|---|-------|----------------------|----------|-------------|
| 1 | No Twilio anywhere yet | `grep -ri twilio */package.json` | zero hits | Someone started; reconcile ownership before Phase E |
| 2 | Channel gate intact | `notification-template.dto.ts:27` | `SUPPORTED_TEMPLATE_CHANNELS = ['EMAIL']` | Re-anchor Step C1 |
| 3 | Service invariant + comment | `notification-template.service.ts:226-231` | `'Only EMAIL channel is supported'` throw | Re-anchor Step C2 |
| 4 | Dormant SMS guard | `notification-template.service.ts:408-416` | subject/channel_config read-only branch for SMS | DD-14 assumption broken — revise |
| 5 | Unified NotificationLog migration status | admin `prisma/migrations/` + `schema.prisma:309-335` | Either landed (channel + generalized recipient present) → skip Step B1 wait; or not landed → B1 blocks send-code merge (M3) | If a *second* SMS-specific log migration exists anywhere: release-constraint violation, halt |
| 6 | Scheduling build delivered the SMS gate | worker dispatcher module: SMS-SKIP pass + `channel='EMAIL'` select + by-id assertion | present, with SKIP reason `"SMS provider not integrated"` | Phase H has nothing to flip — resequence after scheduling build |
| 7 | DRR engine phone-extensible interface | DRR deliverable (FR-21): destination-field parameter on the resolution interface | present | Phase F blocks on DRR (M4) — do NOT fork a resolver |
| 8 | Occurrence table + `dedupe_key` | worker/admin `schema.prisma`: `notification_schedule_occurrences.dedupe_key @unique`, `channel`, `recipients_snapshot` | per scheduling plan §2.2 | DD-10/DD-13 anchors move — verify against shipped shape |
| 9 | rawBody on for signature verification | `external-api-service/src/main.ts:9` | `NestFactory.create(AppModule, { rawBody: true })` | Webhook signature step needs boot change first |
| 10 | Phone source column | admin `schema.prisma:1029` | `Exhibitor.phone String @db.VarChar(20)` NOT NULL | Allow-list default (DD-3) re-targets |
| 11 | ppl_settings machinery | `ppl-settings.service.ts:13-60` + seeder | typed getters + TTL cache + invalidate | DD-2 tunables path re-plans |
| 12 | Admin migration head | `ls admin-backend-api/prisma/migrations | tail -1` | note current head | Step D1 migration is named/sequenced after it |
| 13 | Twilio idempotency capability (Phase A R&D) | Twilio docs/test account: request-idempotency mechanism on Messages create | documented mechanism, or confirmed absent | DD-10 falls back to platform-side guard only — record in revision |

---

## Implementation Order

Phases map the combined-release sequencing: **Scheduling build → unified migration (DRR-track, M3) → email DRR → SMS phone extension (M4) → gate flip last.** Phase A runs from day one in parallel with everything.

| Step | File / deliverable | Action | Est |
|------|--------------------|--------|-----|
| 0 | Substrate Verification (above) | VERIFY | 1.0h |
| A1 | SMS-01 + SMS-02 question pack to client/BA; on confirmation: Twilio account + 10DLC brand/campaign registration kickoff (owner per SMS-08) | PROCESS (day one) | 2.0h |
| A2 | Twilio test credentials + sandbox; idempotency-mechanism R&D (check #13) | PROCESS/R&D | 2.0h |
| B1 | Consume the unified `NotificationLog` migration: `db push` mirror ×4 repos; verify backfill `channel='EMAIL'` + legacy `email` column intact (DRR-S2) | VERIFY/MODIFY | 2.0h |
| C1 | `notification-template.dto.ts` — channel widen + `SmsChannelConfigDto` | MODIFY | 3.0h |
| C2 | `notification-template.service.ts` — SMS validation branch | MODIFY | 4.0h |
| C3 | Seeders — SMS predefined rows scaffold + `ppl_settings` keys | MODIFY | 3.0h |
| D1 | Migration: `sms_suppressions`, `sms_consent_events`, `twilio_webhook_events` | CREATE | 3.0h |
| D2 | `sms-compliance.service.ts` — suppression check + quiet hours | CREATE | 6.0h |
| E1 | Worker: `twilio` dep + env validation + config wiring | MODIFY | 2.0h |
| E2 | `sms.service.ts` + `sms-render.util.ts` + `sms-phone.util.ts` | CREATE | 8.0h |
| E3 | Dispatcher pre-send pipeline + channel switch + dedupe guard (flip still OFF) | MODIFY | 6.0h |
| F1 | Shared-engine phone extension consumption: allow-list phone columns + snapshot phone destination | MODIFY | 4.0h |
| G1 | Twilio status-callback webhook (controller + service + archive + env) | CREATE | 6.0h |
| H1 | Gate flip: remove SMS-SKIP pass, widen select, by-id SMS branch, kill-switch SKIP reason | MODIFY | 3.0h |
| T1 | Test suites (all repos, incl. compliance cases) | CREATE/MODIFY | 14.0h |
| — | Multi-PR coordination buffer (≥5 PRs across 5 repos: rebase/integration/review) | BUFFER | 4.0h |
| — | **Total** | | **73.0h** |

Header/metadata `estimate: 73.0h` equals the table sum (V-043). ✓

### BLOCKED-ON register

Steps that cannot be **finalized** until a question is answered. The default/recommended path is planned above so the build starts now; each row states what changes with the answer. Question IDs are the refined story's (§12) / gap analysis's stable IDs.

| Step(s) | Blocked on | What changes with the answer |
|---------|-----------|------------------------------|
| ALL (meta-gate) | **SMS-02** | If 76.8 is NOT confirmed pulled forward, this whole plan stands down and the scheduler keeps SKIPping SMS (AC-22 behavior) — zero build work is scoped |
| A1, E1, E2, G1 | **SMS-01** | Mechanism ≠ Twilio Programmable Messaging ⇒ SDK, credential shape, webhook signature scheme, and DD-1/DD-10/DD-12 all re-plan (`PLAN_BLOCKED`); account ownership answer decides who provisions creds/number |
| A1 (registration), production launch gate | **SMS-08** | Registration owner (us vs client) changes who executes the 10DLC steps; per-template sender answer would add a `sender_id` key to `SmsChannelConfigDto` (DD-15 default: no) |
| C3 (seed rows), F1 (per-trigger phone mapping), E3 (D3 trigger classification) | **SMS-06 / SMS-07** | The trigger→SMS list + per-trigger recipient phone field fills `SMS_PREDEFINED_TEMPLATES` (ships as empty scaffold until then) and the allow-list phone-column set; decides whether the dormant `Product.product_purchased_sms_enabled` flag becomes a live trigger or is excluded |
| C1/C2 sign-off | **SMS-15** | `SmsChannelConfigDto` shape + seed-vs-create stance are PROPOSED defaults; a different answer reshapes the DTO before C1 merges |
| D1 (consent capture flow), production go-live | **SMS-03** | Consent policy decides which entity keys `sms_consent_events` GRANT rows and whether prior express consent gates every send; suppression store builds regardless (DD-8). **No US go-live without this answer** |
| B1 (sign-off only) | **SMS-05** | PROPOSED resolved per M3 + release constraint (extend NotificationLog, ONE unified migration, DRR authors); a contrary answer violates the spine — escalate, don't build |
| E1/DD-2 sign-off | **SMS-04** | Credentials/tunables split is the PROPOSED default; a config-UI answer adds an admin screen (out of this plan's estimates) |
| G1/DD-11 sign-off | **SMS-09** | Half-resolved by SMS-01 (Twilio ⇒ status webhooks); retry-policy sign-off locks DD-11 |
| E2/DD-6 sign-off | **SMS-10** | Different length policy changes the cap constants / truncate-vs-fail behavior |
| E2/DD-7 sign-off | **SMS-11** | Different fallback (default number / abort) rewrites the skip+log branch — current default never sends to a substitute number |
| DD-7 region lock | **SMS-12** | International reach replaces the US/CA normalizer with a libphonenumber-class dependency + per-country sender rules (new scope) |
| DD-15 / E3 throttling | **SMS-14** | A confirmed bulk trigger adds a platform-side queue ahead of the Messaging Service pacing (new scope) |
| D2 immediate-path enforcement | **SMS-S1** | Hold-and-release vs transactional exemption for immediate SMS; launch scope has no immediate trigger so D2 ships scheduled-path-only |
| C3 / D2 (internal recipients) | **SMS-S2** | Internal-recipient exemption decides whether admin-entered phone lists (Product flag) bypass consent/suppression/quiet-hours; default: no exemption |
| — (doc action, not a step) | **M1** | User applies the Known-Issues #2/#12 wording fix ("SMS create is gated; storage shape undefined") — register frozen to this pipeline |

### Detailed Steps

#### Step A1: Day-one provisioning kickoff — PROCESS

**The release long pole.** Send the consolidated SMS-01/SMS-02 question pack (gap analysis "Consolidated question checklist" items 1–2) to the client/BA on day one. On SMS-01 confirmation: create/receive the Twilio account (ownership per the answer), start **A2P 10DLC brand + campaign registration** immediately (days-to-weeks; carriers block 100% of unregistered 10DLC traffic since Feb 2025), provision the Messaging Service + number(s). Track as a checklist parallel to all build phases; AC-16 makes it the production launch gate. Registration owner is part of SMS-08.

#### Step A2: Sandbox + idempotency R&D — PROCESS/R&D

Obtain Twilio **test credentials** (magic test numbers) for dev/QA — all build-phase verification runs against these; `sms_sending_enabled` stays `false` everywhere. Execute Substrate check #13 (idempotency mechanism) and record the result against DD-10.

#### Step B1: Consume the unified NotificationLog migration — VERIFY/MODIFY

**Idempotency:** safe (schema mirror). The DRR track authors and lands the ONE migration in admin (M3: immediately after SMS-02, before any SMS send code merges). This step: mirror the schema into worker/exhibitor/external/pulse `schema.prisma` + `db push`; then verify (a) every pre-existing row backfilled `channel='EMAIL'` NOT NULL, (b) generalized recipient column accepts an E.164 string, (c) legacy `email` column still populated (payment-reminder dedupe query returns unchanged results — DRR-S2). **Do NOT author any SMS-side log migration** — a second migration violates the spine (Substrate check #5).

#### Step C1: Channel gate + `SmsChannelConfigDto` — `admin-backend-api/src/admin/notification-template/dto/notification-template.dto.ts` — MODIFY

- Line 27: `SUPPORTED_TEMPLATE_CHANNELS = ['EMAIL', 'SMS'] as const` (the `@IsIn` gate at :279-283 picks it up; error message becomes channel-generic).
- New `SmsChannelConfigDto` (mirrors `EmailChannelConfigDto` at :175-228 structurally): `to_phone_recipients` — array of recipient specs (literal E.164 strings validated `/^\+1\d{10}$/`, and/or `recipient_source`-style references whose grammar is owned by the DRR engine — this DTO delegates reference validation to the shared config-time validator, DD-3). No `sender_id` (DD-15). No subject-related keys.
- Channel-conditional validation: EMAIL payloads validate against `EmailChannelConfigDto` (unchanged); SMS payloads against `SmsChannelConfigDto`.

#### Step C2: Service SMS validation branch — `admin-backend-api/src/admin/notification-template/notification-template.service.ts` — MODIFY

- Beside :229-231: replace the EMAIL-only throw with: unsupported channel → reject; `SMS && !is_predefined` → `'Custom templates support EMAIL channel only'` (DD-14).
- SMS create/update path: `subject` must be null; body present; compute worst-case segment cost via the same GSM-7/UCS-2 rules as DD-6 and return a **warning** above 1 segment (save still succeeds; hard reject only above `SMS_MAX_SEGMENTS` at *dispatch*, not save — templates carry tokens whose resolved length varies).
- The dormant guard at :408-416 is kept verbatim (predefined SMS: subject non-editable, `channel_config` system-controlled) — now exercised by real rows.
- Config normalization mirrors the EMAIL pattern (:265-275): missing keys stored as `[]`/`null`.

#### Step C3: Seeders — MODIFY

**Idempotency:** safe (upsert-by-slug seeder pattern).
- `notification-template.seeder.ts`: add an `SMS_PREDEFINED_TEMPLATES` array — one row per confirmed SMS-06 trigger (`channel: 'SMS'`, `subject: null`, plain-text body, `channel_config` per C1 shape). **Ships as an empty array with a `// BLOCKED-ON SMS-06` marker until the trigger list lands** — the scaffold, seeder wiring, and tests land now (AC-4: after seed, exactly one SMS row per confirmed trigger, no others).
- `ppl_settings.seeder.ts`: `sms_sending_enabled` (`bool`, **default `'false'`**), `sms_quiet_hours_default` (`'08:00-21:00'`), `sms_quiet_hours_overrides` (JSON: `{"FL":"08:00-20:00","OK":"08:00-20:00","WA":"08:00-20:00","TX":{"mon_sat":"09:00-21:00","sun":"12:00-21:00"}}`), `sms_max_segments` (`'3'`). Own keys only — never repurpose `schedule_*` (DD-2).

#### Step D1: Migration — compliance + webhook tables — `admin-backend-api/prisma/migrations/{ts}_sms_compliance_and_webhook_tables/` — CREATE

**Migration owner:** admin-backend-api (others `db push`). **Head:** current head per Substrate check #12 (verified available at implementation time). **Idempotency:** destructive — recover by dropping the three new tables before re-running.

Tables (all Int PKs, NOT NULL unless stated):

- `sms_suppressions` — `id Int @id @default(autoincrement())`, `phone_e164 String @db.VarChar(20) @unique`, `source String @db.VarChar(50)` (`'provider_stop' | 'manual' | 'support'`), `note String @db.Text @default("")`, `released_at DateTime? @db.Timestamptz(6)` (nullable by semantics: re-opt-in timestamp, absent until it happens), `created_at/updated_at Timestamptz`. Rows are never deleted (audit); re-opt-in sets `released_at`; the pre-send check treats `released_at IS NULL` as suppressed.
- `sms_consent_events` — `id Int @id @default(autoincrement())`, `phone_e164 String @db.VarChar(20)`, `action String @db.VarChar(20)` (`'GRANT' | 'REVOKE'`), `source String @db.VarChar(100)`, `exhibitor_id Int?` FK SetNull, `user_id Int?` FK SetNull (nullable by semantics: consent may pre-date an account link; entity keying finalizes with SMS-03), `occurred_at Timestamptz`, `created_at Timestamptz`. **Append-only; ≥5-year retention — explicitly excluded from every purge job** (M2).
- `twilio_webhook_events` — `id Int @id @default(autoincrement())`, `message_sid String @db.VarChar(64)`, `message_status String @db.VarChar(32)`, `payload Json`, `created_at Timestamptz`, `@@unique([message_sid, message_status])` (the idempotency key), `@@index([message_sid])`.

Indexes: `sms_suppressions.phone_e164` unique (above); `sms_consent_events @@index([phone_e164, occurred_at])`.

**Rollback:** `DROP TABLE IF EXISTS twilio_webhook_events, sms_consent_events, sms_suppressions;` — dependent-objects-first, no other table references them. Roundtrip (apply → drop → apply) verified clean before merge.

#### Step D2: `SmsComplianceService` — `background-worker-service/src/notification/sms-compliance.service.ts` — CREATE

- `isSuppressed(toE164)` — `sms_suppressions` lookup where `released_at IS NULL`. Called pre-send on **every** SMS dispatch (AC-12).
- `recordOptOut(toE164, source, note?)` / `recordOptIn(toE164, source)` — upsert suppression + append `sms_consent_events` row. Consumed by the webhook handler (STOP) and by manual registration paths ("any reasonable method", M2 — the admin-facing capture surface for manual opt-outs is a thin internal method this release; UI deferred).
- `quietHoursDeferral(toE164, now)` — derive state via `stateForE164`; read window from `ppl_settings` (override else default); unknown/unmapped area code uses the **most restrictive** configured window (fail-safe). In-window violation returns the next allowed window start **in the recipient's local time zone implied by the state**; the dispatcher defers: occurrence stays `PENDING`, `next_attempt_at = returned Date`, `attempt_count` NOT incremented (DD-9). Scheduled path only at launch; the enforcement point is channel-generic so SMS-S1's answer is configuration.
- Trigger-class escalation (D3): transactional trigger + zero deliverable recipients ⇒ abort-and-alert through the same alert channel the scheduling track's S3 finding establishes; marketing/reminder ⇒ skip-and-log. Classification rides the code-controlled trigger catalog (DRR §3.4's matrix) — consumed, not redefined.

#### Step E1: Worker config — MODIFY

- `package.json`: add `twilio` (pin the major current at implementation time; verify at Phase 0 nothing else pulls it).
- `env.validation.ts`: the three `TWILIO_*` keys, `Joi.string().optional()` (DD-2 — contrast with required SendGrid keys at :28-29). Loaded via the established `.env` + `loadAwsSecrets()` path — never hardcoded.

#### Step E2: `SmsService` + utils — CREATE

`sms.service.ts` (DD-5): constructor/`onModuleInit` reads the three keys; any absent ⇒ "not configured" mode (log once, every send returns `SKIPPED skipReason:'sms not configured'` — mailer precedent :69-81). Send flow:

1. Dedupe guard (DD-10): `dedupeKey` provided and a log row for the occurrence already carries a `provider_message_id` ⇒ return that result, no provider call.
2. Create `NotificationLog` row `PENDING` (`channel:'SMS'`, generalized recipient = E.164 destination, `body` = resolved plain text, `subject: null`, `provider:'twilio'`).
3. Twilio `messages.create({ to, body, messagingServiceSid })` + idempotency token per A2's R&D result; `statusCallback` pointing at the G1 endpoint.
4. Update log `SENT` + Message SID, or `FAILED` + `classifyTwilioError(err)` detail. Never throws.

`sms-render.util.ts` (DD-6): `renderSmsBody` raw split/join `{{token}}`; `computeSegments` — GSM-7 charset detection, single/concat sizes per the DD-6 constants; over `SMS_MAX_SEGMENTS` on the resolved body is a hard failure surfaced to the caller (log `FAILED reason:'body exceeds segment cap'`, no retry, no truncation — AC-7).

`sms-phone.util.ts` (DD-7/DD-9): `normalizeToE164` per DD-7 rules; `stateForE164` NANP area-code→state constant map (US/CA; unknown → `null`).

#### Step E3: Dispatcher pre-send pipeline — MODIFY (scheduling-build dispatcher module; path verified Phase 0)

The `channel==='SMS'` branch (behind the still-ON SKIP pass until H1) runs, in order: `sms_sending_enabled` check (off ⇒ `SKIPPED "sms sending disabled by config"`) → resolve destination from `recipients_snapshot` (or via the shared engine at dispatch when `resolve_at_send=true` — D1 toggle inherited as-is, default snapshot-at-materialize; snapshot phone PII lifetime bounded by S1 retention) → `normalizeToE164` (fail ⇒ `SKIPPED "invalid or missing phone number"`) → `isSuppressed` (⇒ skip, outcome suppressed) → `quietHoursDeferral` (⇒ defer per DD-9) → `computeSegments` cap → `SmsService.sendSms(..., dedupeKey: occurrence.dedupe_key)` → result mapped through the inherited retry taxonomy (DD-11); `occurrence.notification_log_id` linked exactly as email does. Email branch untouched — `to[]/cc[]/bcc[]/replacements/from_name/reply_to` keep flowing to `sgMail.send`.

#### Step F1: Shared-engine phone extension consumption — MODIFY

After email DRR ships (M4; Substrate check #7): add the confirmed phone columns (per SMS-07/SMS-06 mapping; default `Exhibitor.phone`) to the per-anchor allow-list the engine validates against (config-time validator in admin beside `assertPlaceholdersAllowed`, materialize-time in the worker — both points, unchanged semantics), and pass the SMS destination-field parameter through DRR's phone-extensible interface. `recipients_snapshot` gains the phone destination field without disturbing the email fields. **No resolver code is written in this step** — it is allow-list data + interface consumption (AC-8: no SMS-specific resolver path exists).

#### Step G1: Twilio status-callback webhook — `external-api-service` — CREATE

`twilio-webhook.controller.ts`: `@Public() @Post('webhook/twilio/sms-status')`; verify `X-Twilio-Signature` with the Twilio SDK validator against the exact raw body + full URL (rawBody already enabled, `main.ts:9`); invalid ⇒ 403, nothing written (AC-19).
`twilio-webhook.service.ts`: insert `twilio_webhook_events` idempotency row (unique `(message_sid, message_status)`; duplicate ⇒ 200 no-op); archive payload to Mongo (365d TTL, `twilio-webhook-archive.service.ts`, Nunify pattern); find `NotificationLog` by `provider_message_id`; map `delivered → 'DELIVERED'`, `undelivered|failed → 'FAILED'` + Twilio error code into `error`; terminal statuses never downgraded (DD-12). Unknown SID ⇒ archive + log warn, 200 (Twilio retries on non-2xx; an unknown SID will not become known).

#### Step H1: Gate flip — MODIFY (one PR; may deploy dark once refined story §9 steps 1–6 are green, in order — launch waits on step 7 [10DLC] + SMS-03, per Rollout steps 3–4)

Per DD-13: remove the SMS-SKIP pass; widen the dispatch select beyond `channel='EMAIL'`; extend the by-id channel assertion with the `channel==='SMS'` → `SmsService` branch (same function family, same log write — scheduling plan §7 phase 6 "flip the send-time gate"). Zero scheduling-schema change, zero re-materialization (AC-21). Production sending still requires flipping `sms_sending_enabled` — the separately-controlled launch lever gated on 10DLC (AC-16).

### Rollout & Rollback

**Rollout (in order):**
1. **Dev/QA** — Twilio test credentials, `sms_sending_enabled=false`; full suite + smoke against test numbers (no live SMS possible).
2. **Staging** — same posture; webhook endpoint reachable by Twilio (test-credential callbacks).
3. **Production, dark** — all code deployed with the SKIP pass still present (pre-H1); then H1 merges with `sms_sending_enabled=false`: SMS occurrences now reach the pipeline and log `SKIPPED "sms sending disabled by config"` — observable, harmless.
4. **Launch** — only when: 10DLC brand+campaign registered, Messaging Service/number provisioned (AC-16), SMS-03 consent decision recorded, §9 checklist fully green. Flip `sms_sending_enabled=true` (a `ppl_settings` edit + SQS invalidate — no deploy).

**Rollback levers (fastest first):**
1. `sms_sending_enabled=false` — instant, no deploy; SMS occurrences skip-by-config; email unaffected.
2. Revert the H1 PR — restores the materialize-then-SKIP posture exactly (the pass and narrow select return; occurrences that already dispatched stay SENT — permanent audit is never rewritten).
3. Schema: all new tables are additive; D1's documented DROP script if ever needed. The unified NotificationLog migration's rollback is owned by the DRR plan.

---

## Tests

**Total: ~62 tests across 7 files** (counts finalized at implementation; compliance cases are mandatory, marked ▲).

| File | Count | Coverage |
|------|-------|----------|
| admin `notification-template` suites (MODIFY) | ~12 | Channel gate, SMS DTO, custom reject, guard, seeder |
| worker `sms-phone.util.spec.ts` | ~8 | E.164 + state map |
| worker `sms-render.util.spec.ts` | ~8 | Rendering + segmentation |
| worker `sms-compliance.service.spec.ts` | ~10 | Suppression + quiet hours ▲ |
| worker `sms.service.spec.ts` | ~10 | Transport, logging, dedupe, error classes |
| worker dispatcher suite (MODIFY) | ~8 | Pipeline order, flip/pre-flip, email regression |
| external `twilio-webhook.spec.ts` | ~6 | Signature, idempotency, status mapping |

**Side-effect boundaries:** Twilio SDK fully mocked in all unit suites (no live network); DB via the repos' existing test harness; time via injected clock/fake timers for quiet-hours and deferral math; webhook signature tested with locally computed HMACs against fixture raw bodies. Live smoke uses Twilio **test credentials only** (magic numbers), `sms_sending_enabled=false` everywhere.

### admin-backend-api (~12)

- `create predefined SMS accepted` — `channel:'SMS'`, `is_predefined:true`, valid config ⇒ 201; the `'Only EMAIL channel is supported'` gate no longer fires (AC-3)
- `create custom SMS rejected` — `is_predefined:false` ⇒ 400 `'Custom templates support EMAIL channel only'` (AC-3/DD-14)
- `create EMAIL unchanged` — existing EMAIL create fixtures pass byte-identical (regression)
- `SMS subject must be null` — subject supplied ⇒ rejected; stored rows carry `subject: null` (AC-5)
- `SmsChannelConfigDto literal validation` — `+1XXXXXXXXXX` accepted; `5551234`, email strings, `+44…` rejected
- `SmsChannelConfigDto reference delegation` — `recipient_source`-style entry routed to the shared config-time validator (AC-8 config half)
- `predefined SMS guard` — update to `subject`/`channel_config` on a predefined SMS row rejected exactly per the :408-416 guard (AC-5)
- `segment warning at save` — body > 160 GSM-7 worst-case ⇒ response carries the warning, save succeeds (DD-6)
- `unicode cost surfaced` — UCS-2 body reports 70-char segmenting
- `seeder: one SMS row per confirmed trigger, none extra` (AC-4) + `seeder idempotent on re-run`
- `ppl_settings keys seeded with defaults` — `sms_sending_enabled='false'` etc.

### worker `sms-phone.util` (~8)

- 10-digit ⇒ `+1XXXXXXXXXX`; 11-digit leading 1 ⇒ `+1…` (AC-9)
- digits-with-formatting (`(617) 555-0100`) normalizes; 9-digit / 12-digit-no-1 / empty / null ⇒ `null`
- known malformed `+`-prefixed over-length shape (`'+1617555082713'` — the Swagger doc-example value, `shows-management.controller.ts:182`; not seed data) ⇒ `null` (skip path, AC-9)
- genuinely seeded `+`-prefixed row (`'+15551234567'`, `exhibitor.seeder.ts:54` — violates the digits-only stored format but is 11-digit-leading-1) ⇒ normalizes to `+15551234567`, not `null`
- non-US/CA (`+44…`) ⇒ `null` (AC-26)
- `stateForE164`: FL/TX/WA area codes map; unknown area code ⇒ `null`

### worker `sms-render.util` (~8)

- `{{token}}` substitution raw, no HTML escaping, no layout markup (AC-6)
- GSM-7 160 chars = 1 segment; 161 = 2 (concat 153); 459 = 3; 460 ⇒ over-cap
- UCS-2 detection: one emoji flips encoding; 71 UCS-2 chars = 2 segments
- over-cap resolved body ⇒ hard-failure result, untruncated (AC-7)

### worker `sms-compliance.service` (~10, compliance ▲)

- ▲ suppressed number ⇒ `isSuppressed` true; dispatch path makes no provider call, outcome `suppressed` (AC-12)
- ▲ `recordOptOut` from STOP source + from manual source both insert suppression + consent REVOKE event (AC-13)
- ▲ released (`released_at` set) number is sendable again; re-opt-out re-suppresses
- ▲ consent events are append-only and queryable ≥5y (no purge touches the table — assert exclusion) (AC-15)
- ▲ FL 8:30pm ⇒ deferred to next 8:00am; TX Sunday 10am ⇒ deferred to noon; default-state 9:30pm ⇒ deferred (AC-14)
- ▲ deferral returns window start; dispatcher applies it without incrementing `attempt_count` (DD-9)
- ▲ unknown area code uses most-restrictive window (fail-safe)
- ▲ D3 split: transactional trigger + zero recipients ⇒ abort-and-alert; reminder trigger ⇒ skip-and-log (AC-10)

### worker `sms.service` (~10)

- missing any `TWILIO_*` key ⇒ not-configured mode: `SKIPPED`, no throw, no client init (AC-1)
- successful send: log written PENDING **before** the provider call, updated SENT with Message SID, `provider:'twilio'`, `channel:'SMS'`, E.164 in generalized recipient (AC-17)
- provider error ⇒ log FAILED + error detail; method resolves (never throws)
- `classifyTwilioError`: 5xx/timeout ⇒ transient; invalid-number/auth/blocked ⇒ hard (AC-20/DD-11)
- dedupe guard: existing log row with `provider_message_id` for the `dedupeKey` ⇒ no second provider call (AC-23)
- statusCallback URL attached to every send

### worker dispatcher (~8)

- pre-send pipeline order: kill switch → resolve → normalize → suppression → quiet hours → cap → send (each short-circuit asserted)
- kill switch off ⇒ occurrence `SKIPPED "sms sending disabled by config"` (AC-16)
- pre-flip: SMS occurrences SKIP `"SMS provider not integrated"` — preserved until H1 (AC-22)
- post-flip: due SMS occurrence dispatches via the by-id path, links `notification_log_id`, zero schema change asserted (AC-21)
- both-channel trigger: EMAIL and SMS rows both dispatch — SMS additive, email not suppressed (AC-11)
- transient failure ⇒ PENDING + backoff `[5m,30m,2h]`, max 3; hard ⇒ immediate FAILED/SKIPPED (AC-20)
- email-only regression: EMAIL occurrences flow byte-identically pre/post flip (AC-18 behavior half)
- `resolve_at_send=true` SMS rule ⇒ engine called at dispatch (D1 branch; skipped/pending until DRR hook ships)

### external `twilio-webhook` (~6)

- valid signature + `delivered` ⇒ log row `'DELIVERED'` by `provider_message_id`; payload archived (AC-19)
- `undelivered`/`failed` ⇒ `'FAILED'` + Twilio error code in `error`
- invalid signature ⇒ 403, no row changes (AC-19)
- replayed callback ⇒ idempotent no-op (unique row) (AC-19)
- out-of-order: `sent` after `delivered` does not downgrade (DD-12)
- unknown SID ⇒ archived + 200, no crash

### Tests Deferred

| Test | Reason |
|------|--------|
| Immediate-path quiet-hours behavior | BLOCKED-ON SMS-S1; no immediate SMS trigger in launch scope (DD-9) |
| Per-trigger seeded-template content assertions | BLOCKED-ON SMS-06 trigger list (scaffold test asserts empty-list invariant meanwhile) |
| Live delivery smoke on a registered number | Post-10DLC only (AC-16); run as part of the launch checklist, not CI |

---

## Backward Compatibility

**Existing contract preserved:**
- Email dispatch, rendering, and logging byte-identical: no email-path file changes except the dispatcher select widen + channel branch (email branch untouched, DD-13); existing mailer/dispatcher tests pass without modification.
- `NotificationLog`: every pre-existing row backfilled `channel='EMAIL'` NOT NULL; legacy `email` column kept + populated (DRR-S2) so the payment-reminder dedupe query (`payment-reminder.service.ts:225-233`) returns unchanged results — verified in Step B1 (AC-18).
- Template CRUD: EMAIL create/update DTO validation unchanged; the widened `@IsIn` accepts a superset; error-message text change on the channel gate is the only observable delta (release-notes it).
- Occurrence pipeline: dedupe identity, state machine, retry taxonomy, S1 retention, catch-up — all inherited unchanged; `recipients_snapshot` extension is additive (email fields untouched).
- Seeder re-run is idempotent; EMAIL rows untouched.

**Deprecations:** none.

---

## Security Considerations

- **Secrets:** `TWILIO_ACCOUNT_SID`/`TWILIO_AUTH_TOKEN`/`TWILIO_MESSAGING_SERVICE_SID` via `.env` + AWS Secrets only (never in DB, code, or logs — DD-2). The auth token doubles as the webhook signature secret: it lives in external-api-service env too, same handling.
- **Webhook:** `X-Twilio-Signature` verified against the exact raw body + full public URL before any processing; invalid ⇒ 403 with no side effects; idempotency rows prevent replay effects (DD-12).
- **PII:** phone numbers in `recipients_snapshot` are bounded by the S1 retention purge (~90d `schedule_occurrence_retention_days`) — SMS must not assume snapshots persist; suppression/consent tables hold numbers permanently by design (compliance records, M2), access via service layer only; log `body` holds resolved message text — same posture as email log rows (permanent audit, never edited/deleted).
- **Compliance gates (M2):** suppression checked pre-send on every dispatch; state-aware quiet hours enforced; consent events retained ≥5 years; **no production traffic before A2P 10DLC registration** (carrier hard-block since Feb 2025) — enforced procedurally by AC-16 + the default-off kill switch.
- **Access control:** all SMS admin surface rides the existing notification-template permissions (FR-17); no new roles.

---

## Deferred

- **Custom SMS templates** — custom stays Email-only (DD-14); revisit only if the V2 two-epic model changes.
- **Provider-config admin UI** — none this release (SMS-04 PROPOSED); revisit if SMS-04's answer demands it.
- **International SMS** — US/CA-only launch (DD-7); owner: future SMS-12 decision (provider plan, per-country cost, sender-ID rules).
- **Per-template sender identities / SMS sender whitelist table** — single global Messaging Service (DD-15); revisit on SMS-08.
- **Immediate-trigger SMS + its quiet-hours mechanism** — no confirmed immediate trigger (SMS-06); SMS-S1 owns the quiet-hours question; enforcement point already channel-generic (DD-9).
- **Capture-time phone-data debt** — fail-open `@IsValidPhone`, malformed stored rows, `validatePhoneDeep` line-type screening: data-debt register item; dispatch-time normalization is the in-scope guard (DD-7).
- **Email path's ignore-`channel_config`-at-dispatch gap + four-mailer drift** — recorded for the register (refined story FR-4 note), not fixed here.
- **Event/workshop/show-date anchors** for the two client-cited scheduled SMS — scheduling track deferred scope (P9-2); the provider flip alone does not make them dispatchable.
- **Inbound SMS conversation handling** beyond STOP/HELP capture — in no story text; revisit only on a new story.
- **Platform-side bulk queue** — Messaging Service pacing suffices absent a confirmed bulk trigger (SMS-14, with SMS-06).

---

## Cross-Cutting Impact Ledger

| Affected atom / module | What it consumes | Change | Disposition | Verification |
|------------------------|------------------|--------|-------------|--------------|
| Scheduling dispatcher (EMS-766-SCHED) | dispatch select `channel='EMAIL'`; SMS-SKIP pass; by-id assertion | H1 flips all three | Update-in-this-plan (Step H1, per scheduling plan §7 phase 6 — the flip is the scheduler's own designed seam) | dispatcher suite: pre/post-flip + email regression |
| DRR engine (EMS-779-DRR) | per-anchor allow-list; destination-field interface (FR-21) | + phone columns; phone-field consumption | Update-in-this-plan (Step F1) — engine internals untouched | AC-8 test: no SMS-specific resolver path |
| Unified NotificationLog migration (DRR-owned) | — | SMS requirements on its shape (DD-4) | No-op here — spec'd in DRR FR-18/DRR-S2; this plan only verifies (Step B1) | B1 backfill + dedupe-query checks |
| Four mailer copies (admin/exhibitor/external/worker) | `NotificationLog` writers | new `channel` column NOT NULL default-backfilled | No-op — writers unchanged; DB default/backfill covers them (email rows get `'EMAIL'`) | AC-18; existing mailer tests unchanged |
| `payment-reminder.service.ts` dedupe query | `NotificationLog.email` | column kept + populated (DRR-S2) | No-op — protected by the DRR migration's own contract | B1 verification query |
| Template CRUD consumers (admin UI, listing/filter) | `SUPPORTED_TEMPLATE_CHANNELS`, channel attribute | SMS rows now exist; listing already supports the channel attribute | No-op — additive rows | admin suite regression |
| `recipients_snapshot` consumers (dispatcher email branch) | snapshot JSON shape | additive phone destination field | No-op — email fields untouched (DD-13) | dispatcher email regression test |
| SonarQube gates ×5 | new code | new files/branches | No-op — standard gates; duplication gate satisfied by native-per-repo rule | `scripts/check-sonar.sh` per repo |

---

## Post-Atom Checklist

1. Registry/tracker — EMS-768-SMS marked complete + date; Jira SBE ticket (assigned at sprint cut) moved per workflow; DEV DONE description = routes-only table (`POST /webhook/twilio/sms-status`).
2. Aggregate counts — live test counts match Tests section actuals across the 5 repos.
3. Changelog / release notes — SMS entries added to the combined-release notes set.
4. Plan archived — this file updated with final state (status → implemented).
5. **User reviews and commits per repo — no auto-commit/push (project convention; commit scope = Jira ticket id).**
6. Known-issues register actions surfaced to the user: M1 wording fix (#2/#12) still pending user application; email `channel_config`-at-dispatch gap + four-mailer drift recorded.
7. Un-gating checklist (refined story §9) stored with the release runbook; launch flip (`sms_sending_enabled`) executed only per AC-16/AC-24.
8. Provisioning artifacts recorded: Twilio account owner, Messaging Service SID (in secrets only), 10DLC brand/campaign IDs + registration dates.

---

## Quality Gates

- All new/modified test suites passing across the 5 repos ({N} new tests per the Tests section; 0 existing tests broken)
- Lint + typecheck: 0 issues, all 5 repos (pipeline step 2)
- gitleaks: 0 findings (no credential ever in code — DD-2)
- SonarQube quality gate green ×5, incl. duplication gate (one shared engine; native-per-repo services carry no copied code)
- Migration roundtrip clean: D1 apply → rollback script → apply
- `db push` mirrors in sync: `prisma migrate diff` between admin schema and each mirror = empty
- Pre-flip/post-flip dispatcher regression suite green (email byte-identical)

---

## Verification

```bash
cd /Users/uipl/Desktop/uipl/sbe/APIs

# Phase 0 substrate spot-checks
grep -rn "twilio" admin-backend-api/package.json exhibitor-backend-api/package.json \
  background-worker-service/package.json external-api-service/package.json \
  pulse-broker-service/package.json                       # Expected pre-build: no hits; post-E1: worker + external only
grep -n "SUPPORTED_TEMPLATE_CHANNELS" \
  admin-backend-api/src/admin/notification-template/dto/notification-template.dto.ts
                                                          # Expected post-C1: ['EMAIL', 'SMS']

# Unit suites (per repo)
cd admin-backend-api && npm test -- --testPathPattern=notification-template   # Expected: all pass incl. ~12 SMS cases
cd ../background-worker-service && npm test -- --testPathPattern="sms|dispatch"  # Expected: ~36 SMS tests pass
cd ../external-api-service && npm test -- --testPathPattern=twilio-webhook    # Expected: ~6 pass

# Migration + mirrors
cd ../admin-backend-api && npx prisma migrate status      # Expected: sms_compliance_and_webhook_tables applied
npx prisma migrate diff --from-schema-datamodel prisma/schema.prisma \
  --to-schema-datamodel ../background-worker-service/prisma/schema.prisma     # Expected: no drift on shared models

# Log backfill (after unified migration — Step B1)
# psql: SELECT COUNT(*) FROM notification_logs WHERE channel IS NULL;         # Expected: 0
# psql: SELECT COUNT(*) FROM notification_logs WHERE channel <> 'EMAIL';      # Expected: 0 (pre-SMS-send)

# Pre-flip behavior (before H1)
# psql: SELECT status, COUNT(*) FROM notification_schedule_occurrences
#       WHERE channel='SMS' GROUP BY status;              # Expected: SKIPPED rows, reason "SMS provider not integrated"

# Kill switch (after H1, before launch)
# psql: SELECT config_value FROM ppl_settings WHERE config_key='sms_sending_enabled';  # Expected: 'false'

# CI + Sonar
./scripts/check-pipelines.sh                              # Expected: latest pipeline green ×5
./scripts/check-sonar.sh                                  # Expected: quality gate OK ×5
```
