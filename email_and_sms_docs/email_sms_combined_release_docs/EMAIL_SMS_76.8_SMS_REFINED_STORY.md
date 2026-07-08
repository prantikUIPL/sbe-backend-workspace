# Email & SMS — Story 76.8 Refined User Story: Integrate an SMS Provider

**Module:** Email & SMS Management → SMS delivery (predefined epic 76)
**Supersedes:** the one-line Updated-Epic story 76.8 ("Integrate an SMS provider (Client dependency on provider)") and the V2/Confluence 76.8 story text (Navigation + System Spec + Design Spec + Acceptance Criteria, hedged throughout with "(Subject to client confirmation)" / "(Subject to R&D)"). Those remain on disk / on Confluence as the historical baseline.
**Date:** 2026-07-08
**Audience:** Product / BA / Sprint planning
**Release context:** part of the **combined release** — Scheduling (76.6/77.8) + Dynamic Recipient Resolution (77.9) + SMS provider (76.8) ship **together**. Shared spine: **one** recipient-resolution engine (the DRR service generalizes the scheduler's restricted resolver; SMS extends that same engine to a phone field), **one** unified `NotificationLog` migration (channel + generalized recipient), and the **D1** per-rule resolve-timing toggle (default = snapshot-at-materialize). The release long pole is provider provisioning (Twilio account + A2P 10DLC brand/campaign registration, days-to-weeks) — it must start day one.
**Primary source material:** `EMAIL_SMS_76.8_SMS_PROVIDER_INTEGRATION_GAP_ANALYSIS.md` (2026-07-06 — the authoritative gap/question register for this story, SMS-01…SMS-15).
**Secondary sources:** Confluence 76.8 story (SBE — Exhibitor Store / Email & SMS pages) and `Email & SMS Management V2.xlsx` (the fullest story text); `Email & SMS Management Upadated Epic.xlsx` (76.8 stub, row 55); V1 `Email & SMS Management.xlsx` (SMS display rules only — no provider story); external plan-validation report (findings M1–M4 on the SMS surface; D1/D3/S1/S2/S6 where they touch SMS); `EMAIL_SMS_SCHEDULING_IMPLEMENTATION_PLAN.md` (Revision 3, approved — READ-ONLY) and `EMAIL_SMS_SCHEDULING_STORY.md` (AC-15/16, the SMS gate this story un-gates).
**Companion documents (combined release):** the 77.9 DRR refined story (owns the generalized resolver + the unified `NotificationLog` migration shape + D1), the scheduling fixes addendum, and the combined-release plan set under this folder.

> **Labeling convention (used on every requirement):**
> - **CONFIRMED** — settled by a named source (story text, approved plan, code reality, or release constraint); no further sign-off needed.
> - **PROPOSED (id)** — our recommended default; signing off this story signs off the default. The id names the open question it hangs on.
> - **OPEN (id)** — a pure question; no default is safe to assume.

---

## 1. User story

> *As the platform (system-level capability, surfaced to Admins through the existing Email & SMS template module), I want SMS-channel notification templates to be delivered through an integrated SMS provider — per their trigger events and scheduling configuration, to recipients resolved by the shared recipient-resolution engine, with compliant consent/opt-out handling and a permanent audit trail — so that time-critical notifications (e.g. workshop confirmations) reach exhibitors and staff by text as the client's template list requires.*

There is **no standalone SMS screen**: V2's Navigation/Design Spec states this is "a system-wide integration definition… not a standalone screen" operating "at the system/backend level" (V2 rows 1008/1048; Confluence 76.8 mirrors it) — **CONFIRMED**. Admin-facing surface is limited to (a) the existing template CRUD once SMS template creation is unlocked, and (b) an optional provider-config UI which V2 leaves conditional ("if required … Subject to R&D") — see FR-2.

---

## 2. Why this refinement exists

1. **76.8 is a late-added story that never settled.** V1 has no provider story at all (zero "provider" mentions; SMS exists only as a template *display* channel). The Updated Epic adds a one-liner (row 55). Only V2/Confluence expands it into a full story — and even there almost every operative clause is tagged "(Subject to client confirmation)" or "(Subject to R&D)". The gap analysis concludes the story text "describes intent rather than settled requirements." This refinement converts that intent into labeled, testable requirements.
2. **The provider was named out-of-band — and the name doesn't send SMS.** A Sprint-6 update identified the provider as **SendGrid** (recorded only in the gap analysis; the May 2026 client-feedback thread contains **no** SMS provider discussion — the word "SMS" appears there only in the subject line). But SendGrid is already our **email** transport (`@sendgrid/mail ^8.1.6`) and **SendGrid's API is email-only — it has no SMS send endpoint**. A2P SMS in that vendor family is **Twilio Programmable Messaging** (Twilio owns SendGrid). The mechanism must be **confirmed with the client (SMS-01), never silently assumed** — see §4.
3. **The last recorded scope decision says the opposite of this release.** `EMAIL_SMS_KNOWN_ISSUES.md` #2 records 76.8 as "out of scope per verbal BA agreement (2026-06-03) — Documentation only this sprint", and the approved scheduler SKIPs SMS occurrences with reason `"SMS provider not integrated"` (scheduling plan §4 item 10; scheduling story AC-15/16). The combined release **pulls 76.8 forward**; that reversal needs formal confirmation (**SMS-02**) — it is the meta-question gating everything below.
4. **The docs and the code contradict each other on what already exists.** Known-Issues #2/#12 say SMS storage/edit is "already built, zero schema change", but the code hard-blocks SMS template creation (`SUPPORTED_TEMPLATE_CHANNELS = ['EMAIL']`, `admin-backend-api/src/admin/notification-template/dto/notification-template.dto.ts:27,:283`; service throws `'Only EMAIL channel is supported'`, `notification-template.service.ts:229-231`), seeds **zero** SMS rows, and leaves the SMS `channel_config` shape read-only-but-**undefined** (`notification-template.service.ts:408-416`). External-review finding **M1 (HIGH)** requires the register wording be corrected to "SMS create is gated; storage shape undefined" — the register file is frozen to this pipeline, so M1 is **flagged here as an outstanding doc-fix for the user to apply**, not applied.
5. **Compliance was a blind spot.** The story text is silent on consent/TCPA; external-review finding **M2** sharpens it: state-aware quiet hours, opt-out via *any reasonable method* (⇒ a platform-controlled suppression store regardless of provider STOP handling), ≥5-year consent retention, and the hard 10DLC gate (carriers **block** 100% of unregistered 10DLC traffic since Feb 2025). Because the combined release pulls SMS forward, M2's scoping applies **now** — §6 FR-9/FR-10 and §8.

---

## 3. Version reconciliation (which text wins, and why)

| Aspect | V1 | Updated Epic | V2 / Confluence | **Winner** |
|---|---|---|---|---|
| Provider story exists | absent | one-liner (row 55) | full story | **V2/Confluence** — only complete text; Updated Epic adds nothing V2 doesn't restate |
| Provider identity | — | unnamed "client dependency" | unnamed in text; Sprint-6 out-of-band update: "SendGrid" | **Sprint-6 update, corrected for feasibility** — vendor *family* accepted, mechanism = Twilio Programmable Messaging **pending SMS-01** (SendGrid API cannot send SMS, so the literal reading is unimplementable) |
| SMS template shape | "Subject field is not applicable and may be hidden; Body content (SMS message) must be displayed" (V1 row 418); "Recipient fields for SMS channel must display **cellphone placeholders** rather than email addresses" (row 420) | 76.5 SMS Template Edit: Body / Name / Status / Type — no Subject (rows 38-47) | inherits via "Refer User Story Template Edit" | **V1 + Updated Epic carried forward** — they are the only concrete SMS-shape statements anywhere and do not conflict (no subject; body-only; phone recipients). Code already agrees: the dormant SMS update-guard forces subject read-only (`notification-template.service.ts:408-416`) |
| Recipient resolution | "cellphone placeholders" hint | — | DRR story: "System shall resolve mobile-number recipients for SMS-channel templates… delivered via the integrated SMS provider" (V2 rows 1124/1158) | **V2** — explicit delegation to 77.9; mechanics resolved by M4/the shared-engine constraint (§6 FR-6) |
| Dispatch/delivery/audit spec | — | — | delivery per trigger + scheduling, placeholder resolution, delivery-outcome handling (Subject to R&D), permanent audit | **V2** — sole source; hedged clauses become PROPOSED/OPEN items below |

Resolution rule applied: **latest-and-fullest text (V2/Confluence) wins for scope; earlier versions win only where they are the sole concrete statement (V1/Updated-Epic SMS template shape); out-of-band updates win over all text but are corrected for technical feasibility (SendGrid → Twilio mechanism, gated on SMS-01).** The only un-hedged V2 clauses — the audit requirement (log + permanent, non-editable retention) and Admin-only access control — are treated as **CONFIRMED**; every hedged clause is refined into a PROPOSED default or an OPEN question.

---

## 4. Provider mechanism & provisioning (the long pole)

### 4.1 Mechanism — PROPOSED (SMS-01)

- The client named **SendGrid**; SendGrid's API is **email-only**. The proposed (and only feasible in-family) mechanism is **Twilio Programmable Messaging** under the same parent/billing family: add the `twilio` Node SDK, authenticate with **Account SID / Auth Token**, send via a **Messaging Service SID** (or from-number). Nothing in any of the five repos references Twilio today (grep for `twilio|nexmo|vonage|plivo` = zero hits; no `TWILIO_*`/`SMS_*` env keys) — this is a new dependency.
- **SMS-01 (Blocker, Owner: Client/BA):** confirm Twilio Programmable Messaging as the mechanism, and confirm **who provisions/owns** the account and the sending number (client-owned credentials handed to us vs UIPL-provisioned). The existing SendGrid email path is untouched either way.
- The confirmed mechanism resolves the webhook-vs-polling half of **SMS-09** (Twilio delivery receipts are **status-callback webhooks**: `queued → sent → delivered / undelivered / failed`) and narrows **SMS-08** (sender identity = Messaging Service SID or a provisioned, A2P-registered number).

### 4.2 Provisioning & the 10DLC block gate — CONFIRMED (release constraint + M2)

- **Since Feb 2025 US carriers block — not throttle — 100% of unregistered 10DLC traffic** (M2). Therefore: **no SMS in production until the A2P 10DLC brand + campaign are registered and the sending number / Messaging Service is provisioned.** This is a hard pre-launch checklist item (AC-19).
- Registration takes **days to weeks**. Sequencing: putting **SMS-01** to the client is the **day-one action of the release**; account creation + brand/campaign registration begins immediately on confirmation and runs in parallel with all build work. Every other work item in this story can proceed against Twilio's test credentials/sandbox while registration is pending (FR-15).
- Who performs the carrier registration (us vs client) is part of **SMS-08** (Owner: Client).

---

## 5. Navigation & UX

- **CONFIRMED:** no standalone SMS screen; system-level integration (V2 Navigation/Design Spec — §1 above).
- **CONFIRMED:** any exposed provider-config UI must be restricted to Admin users with appropriate role/permissions (V2 Access Control, row 1054).
- **PROPOSED (SMS-04):** **no provider-config UI in this release.** Credentials follow the established env + AWS Secrets pattern (§6 FR-2); behavioral tunables follow the established `ppl_settings` pattern. Admin-visible SMS surface = the template module (SMS rows in Listing/Search/Filter/Detail/Edit, which the listing side already supports for the channel attribute) once FR-3 unlocks SMS rows.

---

## 6. Functional requirements

### FR-1 — Provider integration (PROPOSED — SMS-01)
Integrate **Twilio Programmable Messaging** as the SMS transport: `twilio` SDK dependency in `background-worker-service` (the send host, mirroring where scheduled email dispatch lives), sends addressed via Messaging Service SID. Blocked on SMS-01 confirmation; no account setup or SDK integration before the mechanism is confirmed.

### FR-2 — Credentials & configuration (PROPOSED — SMS-04)
- **Credentials** = environment variables loaded via per-repo `.env` + AWS Secrets (`loadAwsSecrets()` before `ConfigModule`), exactly like `SENDGRID_API_KEY`/`SENDGRID_FROM` (`background-worker-service/src/config/env.validation.ts:28-29`; `exhibitor-backend-api/src/config/phone-validation.config.ts:19-28` precedent): `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_MESSAGING_SERVICE_SID`. Note this is a **different secret set** than SendGrid email even though the vendor family is shared — new provisioning regardless.
- **Absent-credential behavior** mirrors the mailer: "not configured" mode — log + skip, never throw (`background-worker-service/src/notification/mailer.service.ts:69-81` precedent).
- **Tunables** (quiet-hours windows, sandbox toggle, kill switch) = `ppl_settings` rows read through `PplSettingsService` (60s TTL cache + SQS-triggered `invalidate()`, `background-worker-service/src/common/ppl-settings/ppl-settings.service.ts:13-60`). SMS adds its **own** keys; it does not repurpose the scheduler's (`schedule_*`) knobs.
- No DB-stored credentials, no admin config screen (see §5).

### FR-3 — Unlock SMS template existence (PROPOSED — SMS-15)
- Widen `SUPPORTED_TEMPLATE_CHANNELS` to `['EMAIL', 'SMS']` — a deliberate **one-place change** (the service comment at `notification-template.service.ts:226-228` says widening "stays a one-place change"); the DTO `@IsIn` gate and the service invariant both pick it up.
- **Predefined SMS templates are seeded**, one per confirmed trigger in the SMS-06 trigger list (the seeder currently ships **zero** SMS rows — every predefined template is `channel: 'EMAIL'`, `admin-backend-api/src/database/seeds/notification-template.seeder.ts`; the gap doc counted 30 seeded EMAIL templates, the current seeder grep counts 29 — zero SMS either way). Seeding follows the template-ownership rule: this story seeds its own slugs/templates.
- **Custom SMS templates stay out of scope** — custom remains Email-only, consistent with the V2 two-epic model and scheduling story AC-14.
- No schema change on `notification_templates`: the Prisma enum already has both values (`enum NotificationChannel { EMAIL SMS }`, `admin-backend-api/prisma/schema.prisma:241-244`), `channel`/`channel_config Json?`/`subject String?` are already channel-generic (`schema.prisma:262-266`).

### FR-4 — SMS `channel_config` contract (PROPOSED — SMS-15, recipient field deferred to SMS-07)
Define the previously read-only-but-undefined SMS `channel_config` shape as an `SmsChannelConfigDto`:
- `to_phone_recipients` — array of recipient specs for the shared resolution engine (literal E.164 strings and/or `recipient_source`-style references; exact spec owned by the DRR story per FR-6). Mirrors `EmailChannelConfigDto.to_recipients` (`notification-template.dto.ts:175-228`).
- **No sender key per template** — sender identity is the single global Messaging Service (FR-10 default). If SMS-08 lands on per-template senders, a `sender_id` key is added then.
- **No subject** — `subject` stays `null` on SMS rows (V1 row 418; enforced by the existing guard).
- The existing dormant guard behavior is **honored**: on predefined SMS rows, `subject` and `channel_config` remain system-controlled/read-only (`notification-template.service.ts:408-416`) — same tiering philosophy as predefined EMAIL (`PREDEFINED_EDITABLE_CONFIG_KEYS`, `notification-template.service.ts:88-99`).
- **Dispatch must actually read this config.** The email send path validates `channel_config` at CRUD time but ignores it at dispatch (`sendFromTemplate` uses env `SENDGRID_FROM` + caller-supplied `to`; only the audit-note builder reads `from_address`). SMS wires its config into dispatch **from the start** and does not clone that gap. (The email-side gap is flagged for the register, not fixed here.)

### FR-5 — Rendering, length & segmentation (PROPOSED — SMS-10)
- SMS bodies render as **plain text**: no subject, no HTML escaping, no branded Handlebars layout shell (`renderWithLayout`, worker `mailer.service.ts:197-221`, is email-only), no asset URLs. Token substitution reuses the same literal `{{token}}` semantics as email (raw, un-escaped).
- Placeholder resolution before dispatch is **CONFIRMED** (V2 "Refer User Story Template Constants/Placeholders").
- **Length policy (default):** template-body validation warns at one segment (160 GSM-7 / 70 UCS-2 chars) and hard-caps the *resolved* body at **3 segments (~459 GSM-7 chars)**; within the cap the provider auto-splits (standard concatenated SMS); a resolved body exceeding the cap **fails the dispatch as a hard failure** (logged `FAILED`, no retry) rather than truncating mid-sentence. Unicode bodies are allowed but the validator surfaces the UCS-2 segment cost at save time.

### FR-6 — Recipient resolution: one shared engine, extended to phone (PROPOSED — SMS-07; sequencing per M4)
- SMS recipient resolution is **delegated to the shared engine** the DRR story (77.9) generalizes from the scheduler's restricted `recipient_source`/`replacements_map` resolver. **Sequencing (M4): (1) email DRR generalizes the scheduler's resolver; (2) SMS reuses that same resolver extended to a phone field.** No parallel/second resolver, no SMS-specific ad-hoc lookup — this is the release's shared-spine rule.
- Concretely: the per-anchor allow-list gains **phone columns** alongside email columns (e.g. `Exhibitor.phone` — `String @db.VarChar(20)` NOT NULL, `admin-backend-api/prisma/schema.prisma:1029`, the best-candidate default source for exhibitor-facing SMS), and a `recipient_source` on an SMS-channel rule resolves to a phone field instead of an email field. Both validation points (config-time AND materialize-time) apply unchanged.
- Today's DRR/recipient storage is email-only (`RecipientList` validates every entry `IsEmail`, `notification-template.dto.ts:81-97`) — the phone-capable field is part of the DRR story's engine work; this story consumes it.
- **OPEN within SMS-07/SMS-06:** *which entity's phone* is the recipient per trigger (Exhibitor.phone vs order billing phone vs admin-entered lists) — a per-trigger mapping the BA must supply with the trigger list.
- Zero-recipient policy inherits **D3** from the shared engine: skip-and-log for marketing/reminder triggers, abort-and-alert for transactional triggers, never send to zero recipients.

### FR-7 — E.164 normalization & invalid-number fallback (PROPOSED — SMS-11)
- Stored phone data is digits-only 10–15 chars without `+` (`PHONE_DIGITS_REGEX = /^\d{10,15}$/`, `exhibitor-backend-api/src/common/helpers/validators/is-valid-phone.validator.ts:16`), `VarChar(20)/(50)`, validated fail-open with known malformed rows (e.g. the seeder itself stores `'+15551234567'` — `admin-backend-api/src/database/seeds/exhibitor.seeder.ts:54` — violating the digits-only stored format; the `+`-prefixed shape also pervades Swagger doc examples such as `'+1617555082713'`, `shows-management.controller.ts:182` — a doc example, not seed data). Providers require E.164.
- **Default:** a dispatch-time normalization step converts 10-digit (assume `+1`) and 11-digit-leading-1 numbers to E.164; anything else fails normalization. Missing/invalid number ⇒ **skip + log** (occurrence `SKIPPED` with reason `"invalid or missing phone number"` on the scheduled path; `FAILED` log row with error on the immediate path) — never a default number, never aborting sibling recipients; transactional triggers escalate per D3 (abort-and-alert).
- Normalization is a pure function implemented natively where dispatch lives (worker); the exhibitor-repo deep phone validator (`validatePhoneDeep`, line-type/carrier lookup) is **not** called on the send path in this release (capture-time concern, out of scope).

### FR-8 — Triggers: which sends get SMS (OPEN — SMS-06; one PROPOSED default)
- **OPEN:** the trigger→SMS list — which business triggers get an SMS variant, and the recipient per trigger. The only client-attributable SMS asks on record are the two **scheduled** SMS templates cited via the scheduling story: **Workshop Confirmation SMS (−24h on workshop time)** and a **product-question SMS** — both anchored on event/workshop anchors the scheduling build **defers**, so neither is dispatchable at launch even with the provider live. The client-feedback thread itself contains **no** SMS trigger asks.
- **OPEN (within SMS-06):** whether the dormant `Product.product_purchased_sms_enabled` + `notification_product_purchased_phone_numbers` config (`admin-backend-api/prisma/schema.prisma:1288-1291` — admin-entered SMS recipient lists with no consumer today) becomes the **first live SMS trigger** or is explicitly excluded.
- **PROPOSED default (additive-vs-replace):** SMS is **additive** — an SMS-channel template on a trigger fires **in addition to** that trigger's email, never instead of it. The data model already supports this: `channel` is single-valued with one predefined row per `(notification_type, channel)`, so a trigger carries an email row and an SMS row side by side.

### FR-9 — Consent, opt-out & quiet hours (PROPOSED defaults — SMS-03, sharpened by M2; consent policy itself OPEN)
- **OPEN (SMS-03, Owner: Client):** the consent/lawful-basis policy — which entity holds SMS consent (User? Exhibitor? per phone number?) and whether prior express consent is required before texting. No consent substrate exists in any of the five schemas (grep for `consent|opt_in|subscribe` = nothing; the only preference field is `Company.lead_email_preference`, an email-frequency enum, `schema.prisma:859`). **Without this decision SMS cannot legally go live in the US.**
- **PROPOSED (platform suppression store — required regardless of the consent answer):** a platform-controlled suppression table keyed by E.164 number (admin-owned migration; Int PK; NOT NULL columns per schema preferences) recording opt-outs from **any reasonable method** (M2) — provider-reported STOP webhooks *and* manually-registered requests (email, phone call, support ticket). Every SMS dispatch checks the suppression store pre-send; suppressed numbers ⇒ skip + log. Provider account-level STOP handling stays on as defense-in-depth, but the platform store is authoritative.
- **PROPOSED (state-aware quiet hours, M2):** quiet-hour enforcement is **state-aware**, not a flat TCPA 8am–9pm: FL/OK/WA effectively 8am–8pm; TX (from Sep 2025) 9am–9pm Mon–Sat and noon–9pm Sun. Windows are held as `ppl_settings` data (updatable without redeploy). Scheduled SMS occurrences falling inside a recipient's quiet window are **deferred to the next allowed window**, not dropped. See SMS-S1 for the immediate-trigger question.
- **PROPOSED (consent retention, M2):** consent records (grant, source, timestamp, revocation) are retained **≥ 5 years**.

### FR-10 — Sender identity (OPEN — SMS-08; PROPOSED default)
- **OPEN (Owner: Client):** long code vs toll-free vs short code vs alphanumeric; who performs A2P 10DLC / toll-free registration.
- **PROPOSED default:** **one global Messaging Service** (Twilio Messaging Service SID pooling one or more 10DLC-registered long codes), not per-template sender identities. No `AllowedFromDomain`-style whitelist table for SMS in this release (the email whitelist — `schema.prisma:299-307`, enforced at `notification-template.service.ts` `assertFromDomainAllowed` — has no SMS analogue because the sender is a single system-level identity, not admin-selectable).

### FR-11 — Audit: the unified NotificationLog migration (PROPOSED shape per M3 — SMS-05; requirement itself CONFIRMED) — **shared spine**
- **CONFIRMED (V2, un-hedged):** SMS dispatch events are logged with template identifier, resolved recipient reference, dispatch outcome, timestamp; audit retained permanently, non-editable.
- Today this is unimplementable: `NotificationLog` (`admin-backend-api/prisma/schema.prisma:309-335`) has **no channel column** and a single nullable recipient column named `email` (`String? @db.VarChar(255)`; worker writes `email: options.to[0]`, `background-worker-service/src/notification/mailer.service.ts:129-130`).
- **PROPOSED (M3 + combined-release constraint):** extend `NotificationLog` — **not** a separate SMS log table — via the release's **ONE unified migration**, shared with DRR: add `channel` (`NotificationChannel`, **NOT NULL, backfilled `'EMAIL'`** per schema preferences) + the generalized recipient column (exact column shape owned by the 77.9 story, which authors the migration; this story's requirement on it is: it must record an E.164 SMS destination and distinguish channel). Admin-backend owns the migration; the other four repos take it via `db push` (CLAUDE.md). Sequenced **immediately after the scope decision (SMS-02), before any SMS send code** (M3).
- SMS log writes follow the **worker** pattern (the strictest of the four mailer copies): PENDING-first crash-safe write, then update to SENT/FAILED, recording `provider: 'twilio'` + `provider_message_id` (Message SID) — `background-worker-service/src/notification/mailer.service.ts:125-183` precedent. `provider_message_id` is the join key delivery callbacks need (FR-12).

### FR-12 — Delivery-status callbacks & retry policy (PROPOSED — SMS-09)
- **Mechanism (resolved by SMS-01's Twilio answer):** asynchronous **status-callback webhooks** (`queued → sent → delivered / undelivered / failed`), not polling.
- **Receiver:** a new public POST endpoint in **external-api-service**, the established inbound-webhook host, as a third instance of the Stripe/Nunify recipe: `@Public()` route → provider signature verification (**`X-Twilio-Signature`**; app already boots `rawBody: true`, `external-api-service/src/main.ts:9`) → DB idempotency row → Mongo archive → typed handling (`external-api-service/src/modules/webhook/controllers/webhook.controller.ts:36-56` precedent). The handler updates the `NotificationLog` row matched on `provider_message_id` with the final delivery state.
- **Status model:** `SENT` (accepted by provider) is upgraded/annotated by callback outcomes; `undelivered`/`failed` callbacks mark the log row failed with the Twilio error code. (Whether a distinct `DELIVERED` status value is added to the log's string status is a detail the unified-migration doc settles; either way the callback outcome is persisted.)
- **Retry policy:** scheduled SMS adopts the scheduler's existing taxonomy **unchanged** — transient failures → `PENDING` with backoff `[5m, 30m, 2h]`, `MAX_OCCURRENCE_ATTEMPTS = 3`; hard failures (invalid number, suppressed recipient, auth/4xx, over-cap body) → `FAILED`/`SKIPPED` immediately, no retry (scheduling plan §4 item 3). Twilio error codes are classified into that same transient/hard taxonomy — **no new state machine**. Immediate (non-scheduled) SMS sends are single-attempt, mirroring email (no email-layer retry exists anywhere; `NotificationLog.retry_count` is dormant — `schema.prisma:318`, no writers).

### FR-13 — Scheduling un-gate (CONFIRMED contract; PROPOSED idempotency default) — **shared spine**
The approved scheduler materializes SMS occurrences and SKIPs them (`channel='SMS'` rows flipped to `SKIPPED "SMS provider not integrated"`, plan §4 item 10; story AC-15/16). Un-gating is **mechanical, by design — no schema change, no re-materialization**:
1. Remove/replace the SMS-SKIP pass and widen the dispatch select beyond `channel='EMAIL'` (plan §7 phase 6: "flip the send-time gate").
2. Extend the **by-id dispatch** path's channel assertion: the same `notificationTemplateId` function family that asserts `channel==='EMAIL' && is_active` gains the `channel==='SMS'` branch routing to the SMS sender — **same by-id path, same NotificationLog write, not a forked sender**. This inherits the #21 immunity (by-id skips slug lookup entirely).
3. The occurrence `recipients_snapshot` shape generalizes to a phone destination without breaking the existing email fields (`to[]/cc[]/bcc[]/replacements/from_name/reply_to` must keep flowing to `sgMail.send`).
4. **PROPOSED (duplicate-text protection):** the scheduler is explicitly **at-least-once** (S2 — SENDING-reaper reset can re-dispatch). A duplicate SMS is costlier than a duplicate email (compliance + annoyance + spend), so SMS dispatch **adopts provider-side idempotency**: the Twilio send is keyed on the occurrence `dedupe_key` (idempotency key / equivalent send-dedupe mechanism), so a reaper-induced re-claim cannot double-text.
- Prerequisites before the flip, in order: SMS-02 scope confirmation → unified NotificationLog migration (FR-11, per M3 "immediately after the scope decision") → phone-capable shared resolver (FR-6, per M4) → provider provisioned + 10DLC registered (FR-1/§4.2) → gate flip. See §9 for the full un-gating checklist (AC-24).
- **D1 interaction:** SMS scheduled rules use the same per-rule `resolve_at_send` toggle as email, **default = snapshot-at-materialize**; phone numbers frozen into `recipients_snapshot` are PII whose lifetime is bounded by the S1 retention purge (`schedule_occurrence_retention_days`, ~90d default) — SMS must not assume snapshots persist. `resolve_at_send=true` is unavailable until the DRR engine's dispatch-time hook ships, and is mutually exclusive with tz-accurate sending (D1 spec).

### FR-14 — Throttling & bulk sends (PROPOSED — SMS-14)
All SMS egress goes through the **Messaging Service**, which queues and paces sends against the registered numbers' A2P MPS caps (provider-side throttling) — no platform-side rate governor in this release. The open half of SMS-14 (do any triggers fire in bulk large enough to need platform-side queueing beyond that?) stays with the BA alongside the SMS-06 trigger list.

### FR-15 — Sandbox / no-live-send mode (PROPOSED — SMS-14)
A dev/QA safety toggle ships with the integration: Twilio **test credentials** in non-production environments plus a `ppl_settings` kill-switch key (e.g. `sms_sending_enabled`, default off until the 10DLC gate clears) checked at dispatch. When disabled, sends are logged as skipped-by-config, never handed to the provider. This doubles as the production **launch gate** for §4.2.

### FR-16 — Geographic reach (PROPOSED — SMS-12)
**US/Canada-only at launch**, matching the existing phone-validation region lock (`@IsValidPhone` US/CA; `phone-validation.config.ts`). Non-US/CA numbers fail FR-7 normalization and are skipped + logged. International reach is a separate future decision (provider plan, per-country cost, sender-ID rules).

### FR-17 — Access control (CONFIRMED)
All SMS-related admin surface (SMS template rows in the module; the `ppl_settings` toggles) is restricted to Admin users with the existing notification-template permissions (V2 Access Control; mirrors scheduling story AC-17). No new role model.

---

## 7. System specification (engineering shape)

- **Send host:** `background-worker-service` gets an `SmsService` sibling to `src/notification/mailer.service.ts`, same contract (`{ status: 'SENT'|'FAILED', providerMessageId, error }`, never throws, PENDING-first log write). The scheduling dispatcher's channel switch (`template.channel === 'EMAIL' ? mailer : smsSender`) is the branch point. Admin/exhibitor backends get native equivalents **only if** an immediate SMS trigger is confirmed to live there (SMS-06) — per the cross-repo rule, native re-implementation to the same semantics, no shared package (the four mailer copies are the precedent).
- **Schema work** (all admin-owned migrations, others `db push`; Int PKs, NOT NULL + backfill per preferences):
  1. the **unified `NotificationLog` migration** (FR-11 — authored under the 77.9/DRR doc, consumed here; `NotificationLog.id` is already BigInt, a pre-existing exception that stays);
  2. the **suppression store** + consent-record storage (FR-9 — shape finalized once SMS-03 answers land; the table is needed under every consent answer);
  3. **zero changes** to `notification_templates`, `notification_schedules`, `notification_schedule_occurrences` (the SMS gate was designed to flip without schema work).
- **New endpoint:** Twilio status-callback receiver in `external-api-service` (FR-12).
- **New env keys:** `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_MESSAGING_SERVICE_SID` (worker + external-api-service for signature validation). **New `ppl_settings` keys:** `sms_sending_enabled`, quiet-hours window data (FR-9), any SMS-specific caps — added alongside, never repurposing, the `schedule_*` knobs.
- **Shared-spine touchpoints (summary):**

| Spine element | This story's touch |
|---|---|
| One recipient-resolution engine | consumes it, extended to a phone field (FR-6); adds phone columns to per-anchor allow-lists; never a second resolver |
| ONE unified `NotificationLog` migration | prerequisite for any SMS dispatch (FR-11); adds `channel` + uses the generalized recipient for E.164 destinations; migration authored on the DRR track |
| D1 resolve-timing toggle | inherited as-is; SMS default = snapshot-at-materialize; snapshot phone PII bounded by S1 retention (FR-13) |
| Scheduler gates & state machine | flips the `channel='SMS'` SKIP pass + by-id channel assertion (FR-13); inherits dedupe/claim/reaper/retry/catch-up unchanged; joins the existing SKIP-reason vocabulary (adds `"invalid or missing phone number"`) |

---

## 8. Acceptance criteria

Signing off this story signs off the PROPOSED defaults; each AC below is testable and cites the FR it locks in.

**Provider & config**
- **AC-1** (FR-1/FR-2) Given valid `TWILIO_*` credentials in env/AWS Secrets, when the worker boots, then the SMS sender initializes; given missing credentials, sends are logged and skipped ("not configured" mode) and no exception is thrown.
- **AC-2** (FR-2/§5) Given this release, then no admin provider-config screen exists; SMS credentials are not stored in the database.

**Templates**
- **AC-3** (FR-3) Given an Admin creating a predefined template with `channel='SMS'`, when the request passes the SMS DTO validation, then it is accepted (the `'Only EMAIL channel is supported'` gate no longer fires); custom-template creation with `channel='SMS'` remains rejected.
- **AC-4** (FR-3) Given a fresh seed run, then one predefined SMS template row exists per trigger on the confirmed SMS-06 list, and no other SMS rows exist.
- **AC-5** (FR-4) Given an SMS template row, then `subject` is null and non-editable, and on predefined SMS rows `channel_config` is system-controlled (read-only) exactly as the existing guard specifies; the stored `channel_config` validates against the `SmsChannelConfigDto` shape.
- **AC-6** (FR-5) Given an SMS dispatch, then the body sent to the provider is plain text with all `{{tokens}}` resolved, no HTML escaping, and no branded layout/asset markup.
- **AC-7** (FR-5) Given a resolved SMS body exceeding 3 GSM-7 segments (~459 chars), when dispatch runs, then the send is not attempted and the log records a hard failure; bodies of 2–3 segments are sent (provider concatenation) without truncation.

**Recipients**
- **AC-8** (FR-6) Given an SMS-channel rule whose `recipient_source` names an allow-listed phone column (e.g. `Exhibitor.phone`), when the occurrence materializes, then the shared engine resolves the number into the snapshot — via the same engine, same config-time + materialize-time validation as email; there is no SMS-specific resolver code path.
- **AC-9** (FR-7) Given a stored 10-digit US number, when dispatch runs, then it is normalized to `+1XXXXXXXXXX` E.164 before the provider call; given a malformed or missing number, then the occurrence/log is marked skipped with reason `"invalid or missing phone number"`, no provider call is made, and other recipients of the same send are unaffected.
- **AC-10** (FR-6/D3) Given a transactional SMS trigger resolving zero recipients, then the send aborts with an alert; given a reminder/marketing trigger resolving zero recipients, then it skips and logs.

**Triggers**
- **AC-11** (FR-8) Given a trigger carrying both an EMAIL and an SMS predefined template, when the trigger fires, then **both** are dispatched (SMS is additive); no trigger's email is suppressed by the existence of an SMS row.

**Compliance**
- **AC-12** (FR-9) Given a phone number present in the suppression store, when any SMS dispatch targets it, then no provider call is made and the outcome is logged as suppressed.
- **AC-13** (FR-9) Given a provider STOP webhook or a manually-registered opt-out (any reasonable method), then the number is added to the suppression store and takes effect on the next dispatch.
- **AC-14** (FR-9) Given a scheduled SMS occurrence whose fire time falls inside the recipient's state-aware quiet window (e.g. 8:30pm in FL/OK/WA; 10am Sunday in TX), then the send is deferred to the next allowed window, not dropped and not sent in-window.
- **AC-15** (FR-9) Given a recorded consent grant or revocation, then the record (source, timestamp) is retained and queryable for at least 5 years.
- **AC-16** (FR-15/§4.2) Given `sms_sending_enabled` is off (the default until 10DLC registration completes), then no live SMS leaves any environment; dispatches log skipped-by-config. **No production SMS before the A2P 10DLC brand + campaign are registered and the Messaging Service/number is provisioned.**

**Audit & delivery status**
- **AC-17** (FR-11) Given any SMS dispatch attempt, then a `NotificationLog` row exists with `channel='SMS'`, the E.164 destination in the generalized recipient column, template id, outcome, timestamps — written PENDING-first, with `provider='twilio'` and the Message SID in `provider_message_id`; log rows are never updated to erase history and never deleted (permanent audit).
- **AC-18** (FR-11) Given the unified migration has run, then every pre-existing log row reads `channel='EMAIL'` (NOT NULL backfill) and email logging behavior is unchanged.
- **AC-19** (FR-12) Given a Twilio status callback with a valid `X-Twilio-Signature`, then the matching `NotificationLog` row (by `provider_message_id`) is updated with the delivery outcome, the payload is archived, and a replayed (duplicate) callback is idempotent; given an invalid signature, the request is rejected and no row changes.
- **AC-20** (FR-12) Given a transient provider failure on a scheduled SMS, then the occurrence retries on the `[5m, 30m, 2h]` backoff up to 3 attempts; given a hard failure (invalid number, suppressed, auth error, over-cap), then it finalizes immediately with no retry.

**Scheduling integration**
- **AC-21** (FR-13) Given the gate flip has shipped, when a `channel='SMS'` occurrence comes due (and passes suppression/quiet-hours/number checks), then it dispatches through the SMS sender via the same by-id `notificationTemplateId` path as email — and the flip required **zero** scheduling-schema changes and **no** re-materialization of existing occurrences.
- **AC-22** (FR-13) Given the gate flip has NOT shipped, then `channel='SMS'` occurrences continue to materialize and SKIP with reason `"SMS provider not integrated"` (scheduling AC-15/16 behavior preserved).
- **AC-23** (FR-13) Given a SENDING-reaper reset causes a re-dispatch of an SMS occurrence, then the provider-side idempotency key (derived from `dedupe_key`) prevents a second text from reaching the recipient.
- **AC-24** (§9) The launch lever (§9 step 8b, `sms_sending_enabled=true`) is pulled only after the un-gating checklist (§9) is fully green, in order; the H1 code flip (step 8a) may deploy dark once steps 1–6 are green.

**Access & reach**
- **AC-25** (FR-17) Given a non-Admin (or Admin lacking the notification-template permission), then all SMS template/config surface is denied.
- **AC-26** (FR-16) Given a non-US/CA number, then dispatch skips + logs it (US/CA-only launch scope).

---

## 9. Scheduling interaction — the un-gating checklist

Scheduled SMS today = **materialize-then-SKIP** (occurrences carry a denormalized `channel` column; a separate pass flips `channel='SMS'` PENDING rows to `SKIPPED "SMS provider not integrated"` — plan §4 item 10; verification §8 "SMS gate"). The design goal was that turning SMS on is a send-time flip. **Un-gating criteria, in dependency order:**

1. ☐ **SMS-02** answered: 76.8 formally confirmed in scope for the combined release (reversing the 2026-06-03 verbal deferral).
2. ☐ **SMS-01** answered: Twilio Programmable Messaging confirmed; account ownership settled.
3. ☐ **Unified `NotificationLog` migration** landed (FR-11 / M3 — sequenced immediately after SMS-02, before send code).
4. ☐ **Phone-capable shared resolver** shipped (FR-6 / M4 — email DRR first, phone extension second).
5. ☐ **SMS templates exist** for the confirmed trigger list (FR-3/FR-8; SMS-06/SMS-15 answered).
6. ☐ **Compliance substrate live**: suppression store + quiet-hours enforcement + consent decision recorded (FR-9; SMS-03 answered).
7. ☐ **10DLC gate green**: brand + campaign registered, Messaging Service/number provisioned (§4.2; SMS-08 answered).
8. **Flip — two levers, in order:**
   - **8a** ☐ **H1 code flip (deploys dark)**: remove the SMS-SKIP pass, widen the dispatch select, extend the by-id channel assertion (FR-13) — requires steps 1–6 green; `sms_sending_enabled` stays `false`, so the flip deploys dark.
   - **8b** ☐ **Launch**: enable `sms_sending_enabled=true` (FR-15) — requires step 7 (10DLC) green plus the SMS-03 consent decision recorded.

Note the two client-cited scheduled SMS templates (Workshop Confirmation −24h; product-question SMS) additionally depend on the **deferred event/workshop anchors** (scheduling story §6 / SCH-7) — the provider flip alone does not make them dispatchable. Recording, not owning: anchor modelling is the scheduling track's deferred scope.

---

## 10. Out of scope

- **Custom SMS templates** — custom remains Email-only (FR-3; V2 two-epic model).
- **Provider-config admin UI** — deferred unless SMS-04's answer demands it (PROPOSED: none).
- **International SMS** — US/CA-only launch (FR-16; SMS-12 future decision).
- **Per-template sender identities / SMS sender whitelist table** — single global Messaging Service (FR-10 default).
- **Capture-time phone validation improvements** (fixing the fail-open `@IsValidPhone`, backfilling malformed stored numbers, line-type screening via `validatePhoneDeep`) — flagged as data debt; dispatch-time normalization (FR-7) is the in-scope guard.
- **Fixing the email path's ignore-`channel_config`-at-dispatch gap and the four-mailer drift** — recorded for the register (FR-4 note), not fixed here.
- **Event/workshop/show-date anchors** for the client-cited scheduled SMS — scheduling track's deferred scope (§9 note).
- **Inbound SMS conversation handling** beyond STOP/HELP/opt-out capture — not in any story text.

---

## 11. Dependencies

| Dependency | Direction | Detail |
|---|---|---|
| 77.9 DRR (shared resolver + unified log migration) | 76.8 **consumes** | phone-field extension of the one engine (FR-6/M4); the unified `NotificationLog` migration is authored on the DRR track and is a hard prerequisite (FR-11/M3) |
| 76.6/77.8 Scheduling (approved plan) | 76.8 **un-gates** | the `channel='SMS'` SKIP pass + by-id channel assertion (FR-13); inherits occurrence state machine, S1 retention, S2 at-least-once, D1 toggle |
| Client: SMS-01 mechanism + account ownership | blocks FR-1 | day-one question of the release |
| Client: 10DLC brand/campaign registration (SMS-08) | blocks production launch | days-to-weeks; starts immediately on SMS-01 confirmation; hard block gate (AC-16) |
| Client: consent policy (SMS-03) | blocks go-live | suppression store is buildable meanwhile (needed under every answer) |
| BA: trigger list + per-trigger recipient mapping (SMS-06/SMS-07) | blocks FR-3 seeding + FR-8 | includes the dormant Product SMS flag decision |
| Known-issue #21 fix (custom-shadows-predefined) | shared seam | ships with the scheduling logic; the by-id path SMS joins is immune by construction |
| M1 register wording fix (`EMAIL_SMS_KNOWN_ISSUES.md` #2/#12) | user action | register is frozen to this pipeline; correction ("SMS create is gated; storage shape undefined") flagged for the user to apply before client review |

---

## 12. Open questions register

Original stable IDs carried from the gap analysis (SMS-01…SMS-15; SMS-13 retired — settled by architecture: worker sends, admin owns migrations, its fragment folded into SMS-05) and the validation report (M1–M4, D1). New questions raised while writing this story get SMS-Sn ids.

| ID | Question (abbreviated — full text in the gap analysis) | Owner | Status after this story |
|---|---|---|---|
| **SMS-02** | Formally confirm 76.8 is pulled forward into the combined release (reverses the 2026-06-03 verbal deferral) | BA | OPEN — meta-gate; combined release presumes yes, needs written confirmation |
| **SMS-01** | Confirm Twilio Programmable Messaging as the SMS mechanism (SendGrid API is email-only) + account/number ownership | Client/BA | OPEN — FR-1 PROPOSED default hangs on it; **day-one question** |
| **SMS-15** | SMS template existence + `channel_config` contract | BA | PROPOSED defaults in FR-3/FR-4 (seed predefined; custom out of scope; DTO shape; no per-template sender) — needs sign-off |
| **SMS-03** | Consent/opt-in policy: which entity holds consent; prior express consent required? | Client | OPEN — suppression store / quiet hours / 5-yr retention PROPOSED regardless (FR-9, per M2) |
| **SMS-05** | NotificationLog extension vs separate SMS table | BA/Engineering (joint) | PROPOSED resolved per M3 + release constraint: extend, ONE unified migration (FR-11) — needs sign-off |
| **SMS-04** | Where credentials/config live; config UI? | BA | PROPOSED: env + AWS Secrets, no UI, tunables in `ppl_settings` (FR-2/§5) — needs sign-off |
| **SMS-06** | Trigger→SMS list, recipient per trigger, additive-vs-replace, dormant Product flag | BA | OPEN (list + mapping + Product-flag decision); additive default PROPOSED (FR-8) |
| **SMS-07** | Phone source & DRR boundary | BA | PROPOSED resolved per M4 + shared-engine constraint (FR-6); per-trigger phone-field mapping still OPEN with SMS-06 |
| **SMS-08** | Sender identity + who registers 10DLC | Client | OPEN; global-Messaging-Service default PROPOSED (FR-10); registration is the release long pole |
| **SMS-09** | Delivery-outcome capture + retry policy | BA | Half-resolved by SMS-01 (Twilio ⇒ status webhooks); receiver + retry taxonomy PROPOSED (FR-12) — needs sign-off |
| **SMS-10** | Rendering, length/segmentation, unicode | BA | PROPOSED: plain text, 3-segment hard cap, warn-at-1 (FR-5) — needs sign-off |
| **SMS-11** | E.164 normalization + invalid/missing fallback | BA | PROPOSED: normalize US/CA, skip+log fallback, D3 escalation for transactional (FR-7) — needs sign-off |
| **SMS-12** | US/CA-only vs international | Client | PROPOSED: US/CA-only launch (FR-16) — needs sign-off |
| **SMS-14** | Bulk throttling; sandbox mode | BA | PROPOSED: Messaging-Service pacing + `sms_sending_enabled` kill switch (FR-14/FR-15); bulk-trigger question stays OPEN with SMS-06 |
| **SMS-13** | *(retired — architecture answered it; fragment folded into SMS-05)* | — | RETIRED |
| **M1** | Register wording fix: Known-Issues #2/#12 overstate SMS as "already built" | User (register frozen) | OPEN action — flagged in §11, not applied |
| **M2** | 2026 compliance scoping (state quiet hours, suppression store, 5-yr consent, 10DLC block) | Client/BA | Adopted as PROPOSED defaults inside FR-9/§4.2 — signs off with SMS-03/SMS-08 |
| **M3** | Extend NotificationLog (channel + generalized recipient), sequenced before send code | Engineering | Adopted into FR-11/§9 step 3 — signs off with SMS-05 |
| **M4** | Sequencing: email DRR first, SMS extends the same resolver | Engineering | Adopted into FR-6/§9 step 4 — signs off with SMS-07 |
| **D1** | Per-rule `resolve_at_send` toggle (default snapshot-at-materialize) | DRR track (carried here) | Inherited as-is by SMS rules (FR-13); no SMS-specific variance |
| **SMS-S1** *(new)* | Do quiet hours apply to **immediate/transactional** SMS triggers (which fire at any hour), and if so via what mechanism — hold-and-release queue vs send-anyway (transactional exemption)? Scheduled sends defer naturally (AC-14); the immediate path has no deferral mechanism today. | BA/Client | OPEN — new, raised by FR-9 |
| **SMS-S2** *(new)* | Do **internal/staff-facing** SMS recipients (e.g. the admin-entered `notification_product_purchased_phone_numbers` lists) follow the same consent/suppression/quiet-hours rules as customer-facing SMS, or is there an internal-recipient exemption? Affects whether the dormant Product flag can go live without customer-grade consent capture. | BA/Client | OPEN — new, raised by FR-8/FR-9 |

---

*This refined story is documentation only — no code, no schema change, no commits. It proposes defaults for BA/client sign-off; the combined-release implementation plan sequences the build.*
