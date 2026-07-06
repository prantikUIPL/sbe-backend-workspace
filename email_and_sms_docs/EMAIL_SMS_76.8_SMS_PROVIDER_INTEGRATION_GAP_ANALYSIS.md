# Email & SMS — Story 76.8 Integrate an SMS provider: Implementation Gap Analysis

| | |
|---|---|
| **Date** | 2026-07-06 |
| **Sprint** | 6 |
| **Module** | SBE-671 Email & SMS Management |
| **Story** | 76.8 — Integrate an SMS provider |
| **Status** | Pre-implementation gap review |

---

## Purpose

This document lists the blockers and ambiguities that must be confirmed with the BA and client **before** any implementation of Story 76.8 begins. It is a decision-ready "questions to resolve" register: each item states what the story requires, what the codebase actually provides today (with file:line evidence), the resulting gap, why it blocks build, and the precise question to put to the owner.

It is **not** an implementation plan, and it is **not** the dynamic-scheduling track — SMS/email scheduling is designed separately and is out of scope here. This document covers only the provider-integration and SMS-dispatch surface of 76.8. The one place 76.8 and the scheduling track touch — the scheduler's SMS-skip gate — is reconciled in *Interaction with the scheduling track* below; no change to the scheduling plan is proposed.

---

## Story summary

Story 76.8 calls for integrating a third-party SMS provider so that SMS-channel notification templates configured in the module are delivered through that provider per their trigger events. The provider itself is an explicit **client dependency** — the story states the selection and provisioning of the provider "depends on the client (Subject to client confirmation)" (story_sources.txt:6, :28, :58, :67). **Update (Sprint 6): the provider has been identified as SendGrid.** Because SendGrid's API is email-only, the load-bearing follow-on question is now *how* SMS is sent within that vendor family (Twilio Programmable Messaging under the same parent account) — see SMS-01. Substantive clauses cover system-level provider integration and configuration, dispatch of SMS-channel templates to resolved recipients (delegated to the Dynamic Recipient Resolution Engine, story 77.9), handling of the provider's delivery response, and logging of dispatch events. Almost every operative clause is tagged "(Subject to client confirmation)" or "(Subject to R&D)" (story_sources.txt:26-97), meaning the story text describes intent rather than settled requirements.

---

## Current codebase state

What already exists that 76.8 would build on:

- **Channel enum is single-valued (EMAIL xor SMS)** with one predefined template per `(notification_type, channel)`; a trigger could therefore carry both an email and an SMS row.
- **SMS template creation is hard-blocked today** — `SUPPORTED_TEMPLATE_CHANNELS = ['EMAIL']` (notification-template.dto.ts:27, :283); the service throws `'Only EMAIL channel is supported'` (notification-template.service.ts:229-231).
- **Zero SMS rows are seeded** — all 30 predefined templates are EMAIL (notification-template.seeder.ts).
- **SMS rows are read-only on subject + `channel_config`** — controller doc states "On SMS rows subject and the entire channel_config are read-only" (controller.ts:238); the update guard blocks all `channel_config` edits on SMS rows (notification-template.service.ts:408-415).
- **Email send path (the only mailer)** returns synchronously `{status:'SENT'|'FAILED', providerMessageId, error}`, never throws (background-worker-service mailer.service.ts:90-184); renders HTML via Handlebars with a branded layout shell (`renderWithLayout`, :197-221) and literal token substitution (:236-245); writes `email: options.to[0]` to the log (:130).
- **`NotificationLog`** (admin schema.prisma:309-335) has `status` (PENDING→SENT/FAILED), `retry_count`, generic `provider`/`provider_message_id`, and `email String? @db.VarChar(255)` — **no channel column and no phone/to-number column**. Mirrored to worker/pulse schemas via `db push` (background-worker-service/prisma/schema.prisma:286).
- **Existing third-party credentials** (`SENDGRID_API_KEY`, `SENDGRID_FROM`, `PHONE_VALIDATOR_API_KEY`) load from per-repo `.env` + AWS Secrets via `loadAwsSecrets()` before `ConfigModule` (phone-validation.config.ts:19-28); best-fit precedent is a code-resident config with lazy getters, enabled by key presence, fail-open (:29-45). Only email SDK installed: `@sendgrid/mail ^8.1.6`; no `twilio`/`vonage`/`plivo`/`nexmo` anywhere.
- **Email sender identity** uses an `AllowedFromDomain` whitelist (admin schema.prisma:299-307) with `channel_config.from_address` validated against it (service.ts:251). No SMS sender/from-number equivalent exists.
- **Dormant SMS precedent** on the Product model: `Product.product_purchased_sms_enabled` + `notification_product_purchased_phone_numbers` (admin schema.prisma:1289, :1291) — stored/returned only, no consumer dispatches from it.
- **Phone data** is scattered and unnormalized: `User.phone` nullable (schema.prisma:16), `Attendee.mobile` required (:779), `Company.billing_phone`, `Order.billing_phone` (:1594), `OnsiteBoothContact.contact_phone` (:2854), Product phone arrays (:1291); all `VarChar(20)/VarChar(50)` with no E.164 normalization. `@IsValidPhone` (is-valid-phone.validator.ts:113-217) calls PhoneValidator.com live, is region-locked to US/CA, and **fails open** when the key is missing or the API is down.
- **Recipient resolution (77.9)** currently defines EMAIL tokens only and validates every recipient as `IsEmail` (notification-template.dto.ts:81-97) — a phone string cannot be stored as a recipient.
- **Last recorded scope decision:** EMAIL_SMS_KNOWN_ISSUES.md #2 records 76.8 as "out of scope per verbal BA agreement (2026-06-03) — Documentation only this sprint"; the designed scheduler SKIPs SMS occurrences with a `provider-not-integrated` reason until a provider lands (OUTSTANDING_ITEMS §6).

---

## Interaction with the scheduling track (alignment)

The dynamic-scheduling track (stories 76.6 / 77.8) is designed to ship **without** SMS execution — it defers the SMS provider (Known-Issue #2) and implements the deferral mechanically: occurrences carry a denormalized `channel` column and a separate pass flips `channel='SMS'` rows to `SKIPPED "SMS provider not integrated"`, no send attempted (scheduling plan §4 item 10; story AC-15/16). Three consequences for 76.8 — alignment notes only, **no change to the scheduling plan or its companion docs is proposed**:

- **Turning SMS on is a coordinated flip, not just new code.** When 76.8 delivers a working send path, the scheduler's SMS-skip pass is the gate that must be flipped to route scheduled SMS. The scheduling story frames this as "a send-time gate only — zero additional schema or story change" (AC-16). See **SMS-02**.
- **That "zero schema change" claim is scoped to the *scheduling tables* — not the SMS delivery/audit/consent surface.** It holds for `notification_schedules` / `notification_schedule_occurrences`, but the gaps this document raises still require schema/design work *outside* those tables: an SMS-capable audit record (**SMS-05** — `NotificationLog` has no channel/number column), a consent/suppression model (**SMS-03**), and E.164 normalization (**SMS-11**). The two statements are consistent once the scope is read correctly; this note records that so the docs don't appear to contradict.
- **The client has already named specific scheduled SMS templates.** The scheduling story cites client-requested scheduled SMS — "Workshop Confirmation SMS" (−24h) and a product-question SMS — but both anchor on the **event/workshop anchors the scheduling build defers**, so they are not dispatchable until those anchors *and* the SMS provider land. This is source material for **SMS-06** (which triggers send SMS).

---

## Open questions — must confirm before implementation

### Blockers

#### SMS-02 — Is 76.8 actually in scope to build SMS sending this sprint?
| | |
|---|---|
| **Requirement** | V2 specifies full provider integration, dispatch, delivery-outcome handling and audit (story_sources.txt:26-97), but every substantive clause is "(Subject to client confirmation)" or "(Subject to R&D)". |
| **Codebase reality** | SMS template send is gated and unbuilt: `SUPPORTED_TEMPLATE_CHANNELS=['EMAIL']` blocks SMS create (dto:27, :283; service throws at service.ts:229-231), zero SMS rows seeded, no mailer dispatches SMS. KNOWN_ISSUES #2 records 76.8 as out of scope ("Documentation only this sprint", 2026-06-03); the scheduler SKIPs SMS occurrences until the provider lands (OUTSTANDING_ITEMS §6). |
| **The gap** | The story text describes a full send integration, but the last recorded decision deferred SMS sending. Unclear whether 76.8 is being pulled forward to build real dispatch this sprint or remains storage/documentation-only. |
| **Why it blocks** | This meta-question gates every other SMS item — determines whether any need answering now. If still deferred, no build work is scoped; if pulled forward, the provider dependency (SMS-01) becomes an immediate blocker. |
| **Question** | **Is 76.8 in scope to build actual SMS sending this sprint, or does it remain storage/edit-only (send path stays gated) as agreed on 2026-06-03? If pulled forward, has the provider dependency (SMS-01) been resolved?** |
| **Owner** | BA |

> **Scheduling alignment:** the scheduling build already contains the SMS gate — occurrences materialize then `SKIPPED "SMS provider not integrated"` (scheduling plan §4 item 10). Pulling 76.8 forward means flipping that gate, so the scope answer here coordinates with the scheduler, not just this module.

#### SMS-01 — Provider named (SendGrid): confirm the SMS-send mechanism and account ownership
| | |
|---|---|
| **Requirement** | "The specific SMS provider is a client dependency; the selection and provisioning of the provider depends on the client. (Subject to client confirmation)" (story_sources.txt:28; restated :58, :67). Concise AC: "Integrate an SMS provider (Client dependency on provider)" (:6). **Update (Sprint 6): provider identified as SendGrid.** |
| **Codebase reality** | SendGrid is already the **email** transport — `@sendgrid/mail ^8.1.6` with `SENDGRID_API_KEY` / `SENDGRID_FROM` (phone-validation.config.ts:19-28; worker mailer.service.ts). But **no SMS SDK/API exists**: grep for `twilio\|nexmo\|vonage\|plivo` across all five `src/` trees returns zero, and there are no `TWILIO_*`/`SMS_*` env keys (evidence:sms §2, §8). **SendGrid's API is email-only — it has no SMS send endpoint.** |
| **The gap** | Naming "SendGrid" resolves the vendor family but **not** the SMS-send path. SendGrid (a Twilio company) does not send SMS through its own API — A2P SMS in that ecosystem is **Twilio Programmable Messaging**. It must be confirmed whether SMS is sent via the **Twilio Messaging API under the same parent/billing account as the existing SendGrid** (the likely intent — a new `twilio` SDK + Account SID / Auth Token + a Messaging Service or from-number), or via some other arrangement. Account ownership/provisioning (client-owned credentials handed to us vs UIPL-provisioned) is still open. |
| **Why it blocks** | The SDK, credential shape, sender identity (SMS-08), delivery-receipt mechanism (SMS-09), and segmentation/cost (SMS-10 / SMS-14) all hinge on this being the **Twilio Messaging API, not the SendGrid email API**. `@sendgrid/mail` cannot send SMS; the `twilio` integration is a distinct dependency that cannot begin until the mechanism is confirmed. |
| **Question** | **Since SendGrid's API is email-only, confirm SMS is sent via Twilio Programmable Messaging (SendGrid's parent) under the same account — i.e. add the `twilio` SDK with Account SID / Auth Token / Messaging Service — and confirm who provisions/owns that account and the sending number (client-owned credentials handed to us, or UIPL-provisioned).** |
| **Owner** | Client/BA |

#### SMS-15 — How do SMS templates come into existence, and what is the SMS `channel_config` contract?
| | |
|---|---|
| **Requirement** | "SMS-channel templates configured in the module shall be delivered through the integrated SMS provider" (story_sources.txt:60, :73). The send path presupposes SMS templates exist with a defined body + sender configuration. |
| **Codebase reality** | No SMS template can exist today: create is hard-blocked (`SUPPORTED_TEMPLATE_CHANNELS=['EMAIL']`, dto:27/283; service throws at service.ts:229-231) and zero SMS rows are seeded (all 30 predefined are EMAIL, notification-template.seeder.ts). The SMS `channel_config` contract is undefined — no SMS keys (sender_id/originating-number/segment) exist; controller doc declares SMS `channel_config` read-only (controller.ts:238) and the update guard blocks all SMS `channel_config` edits (service.ts:408-415), so the read-only shape was never populated. Docs claim SMS storage/edit is "already built, zero schema change" (KNOWN_ISSUES #2/#12) — a contradiction with the code. |
| **The gap** | Direct contradiction: docs say SMS templates are storable/editable, but code blocks SMS create, seeds no SMS rows, and leaves the SMS `channel_config` shape undefined. Before dispatch, SMS templates must be brought into existence and the SMS `channel_config` contract defined. |
| **Why it blocks** | The send path has nothing to dispatch and no defined config shape. Whether SMS rows are seeded (like the 30 email ones) or created via an unlocked API, and what `channel_config` keys they carry, must be settled before dispatch, rendering, or sender wiring. |
| **Question** | **How do SMS templates come into existence for the send path — seed predefined SMS rows and/or unlock predefined-SMS create (custom SMS stays out of scope)? And define the SMS `channel_config` contract (sender_id / originating number / any segment metadata), since no SMS config keys exist today and the shape was left read-only-but-undefined.** |
| **Owner** | BA |

#### SMS-03 — SMS consent / TCPA / opt-out model
| | |
|---|---|
| **Requirement** | The story is silent on SMS consent/compliance; V2 covers only integration, dispatch, delivery-outcome and audit (story_sources.txt:26-97). Real-world A2P SMS to US numbers requires prior express consent and STOP/HELP handling. |
| **Codebase reality** | No consent substrate exists in any of the five schemas — grep for `consent\|opt_in\|opt-in\|subscribe\|unsubscrib` returns nothing (evidence:schema §a). The only "preference" is `Company.lead_email_preference` (admin schema.prisma:859), a delivery-frequency enum for PPL lead EMAILS — not a channel selector, not SMS-aware. No STOP/unsubscribe tracking, no per-number opt-in flag. |
| **The gap** | SMS has no lawful-basis/consent model. Providers/carriers typically auto-handle STOP/HELP at account level, so the real undefined pieces are: which entity owns SMS consent (User? Exhibitor? per phone number?), whether prior opt-in is required before texting, and whether the platform must persist a suppression list (honoring provider-reported opt-outs) plus TCPA quiet-hours (8am-9pm local). |
| **Why it blocks** | Without a consent/lawful-basis decision and suppression model, SMS cannot legally go live in the US; a suppression store and a pre-send filter are foundational data-model + send-path decisions that must precede dispatch code even if the provider handles STOP keywords. |
| **Question** | **What is the SMS consent/opt-in policy (which entity holds consent, is prior express consent required before sending)? Must we persist a suppression list honoring provider-reported opt-outs and enforce TCPA quiet-hours? This is currently unmodeled and blocks SMS go-live.** |
| **Owner** | Client |

#### SMS-05 — Audit-log storage for SMS dispatch
| | |
|---|---|
| **Requirement** | "SMS dispatch events must be logged including the template identifier, resolved recipient reference, dispatch outcome, and timestamp" and "retained permanently … not editable or deletable" (story_sources.txt:95-97). |
| **Codebase reality** | `NotificationLog` (admin schema.prisma:309-335) has no channel column and no phone/to-number column — recipient is `email String? @db.VarChar(255)` and the worker writes `email: options.to[0]` (mailer.service.ts:130). `provider`/`provider_message_id` are generic enough for an SMS id, but there is nowhere to store the SMS destination number or distinguish EMAIL vs SMS. The model is mirrored to worker/pulse via `db push` (background-worker-service/prisma/schema.prisma:286); per CLAUDE.md admin owns the migration, others `db push`, so the change must originate in admin and propagate. |
| **The gap** | The mandated "resolved recipient reference" for an SMS dispatch has no storage. Undecided whether to add `channel` + phone/recipient columns to `NotificationLog` (admin-owned migration, propagated via `db push`) or create a separate SMS log table. |
| **Why it blocks** | The audit AC cannot be met without a schema change; the shape (extend vs new table, generalize email→recipient) is a data-model decision that must precede the send/log path, and the admin-owned migration must propagate to the db-push repos that run dispatch. |
| **Question** | **Should SMS dispatch reuse `NotificationLog` with new `channel` + phone/recipient columns (admin-owned migration, propagated to the other repos via `db push`), or a separate SMS log table? The current single `email` column cannot record an SMS destination.** |
| **Owner** | BA |

> **Scheduling alignment:** the scheduling story's "zero additional schema change to enable SMS" (AC-16) refers to the scheduling tables only; this `NotificationLog` change is on the delivery/audit surface and is still required.

#### SMS-04 — Where SMS credentials/config live (and any config UI)
| | |
|---|---|
| **Requirement** | "SMS provider integration shall operate at the system/backend level; configuration specifics depend on the selected provider. (Subject to client confirmation)" and "any provider configuration UI (if required) shall be defined based on the selected provider. (Subject to R&D)" (story_sources.txt:58, :64). |
| **Codebase reality** | Existing third-party keys (`SENDGRID_API_KEY`, `SENDGRID_FROM`, `PHONE_VALIDATOR_API_KEY`) come from per-repo `.env` + AWS Secrets via `loadAwsSecrets()` before `ConfigModule` (phone-validation.config.ts:19-28). No SMS key exists. Best-fit precedent is a code-resident config with lazy getters, enabled by key presence, fail-open (:29-45). The SMS toggle/phone-list precedent lives on the **Product** model, not PplSettings; `PplSettings` (admin schema.prisma:2265-2278) is a generic key/value store and a possible DB home for provider config. |
| **The gap** | Where SMS credentials/config live is undecided: env+AWS Secrets (like SendGrid), a DB config row (PplSettings key/value), or an admin-facing provider-config UI. V2 leaves the UI as "if required … Subject to R&D," and if exposed it must be Admin-role gated (:64). |
| **Why it blocks** | Config location determines module structure, whether a new admin CRUD/UI + role-permission wiring is needed, and how the worker (which runs the send) reads the credential. A wrong assumption forces rework of the integration surface. |
| **Question** | **Where should SMS provider credentials/config live — env + AWS Secrets (mirroring SendGrid), a DB config row, or an admin-managed provider-config screen? If a config UI is exposed, confirm it is restricted to Admin role/permissions.** |
| **Owner** | BA |

> **Provider update (SendGrid → Twilio SMS):** the env + AWS Secrets pattern already used for `SENDGRID_API_KEY` is the natural home, but Twilio SMS needs a *different* secret set (Account SID, Auth Token, Messaging Service SID / from-number) — so this is new config to provision regardless of the shared vendor family.

#### SMS-06 — Which triggers send SMS, to whom, and additive-vs-replaces email
| | |
|---|---|
| **Requirement** | "System shall send SMS messages for SMS-channel templates per their trigger events" and "deliver SMS templates to the resolved recipients" (story_sources.txt:32, :36). |
| **Codebase reality** | All 30 seeded predefined templates are channel EMAIL (seeder). No SMS template exists and none can be created via API. `channel` is single-valued (EMAIL xor SMS) with one predefined per `(notification_type, channel)`, so a trigger could carry both an email and an SMS row. The dormant SMS precedent (`Product.product_purchased_sms_enabled` + `notification_product_purchased_phone_numbers`, admin schema.prisma:1289, :1291) has no consumer — grep finds only store/return, nothing dispatches (evidence:sms §5). |
| **The gap** | Undefined which business triggers get an SMS variant (order confirmation? low balance? booth reminders?), who the SMS recipient is per trigger, and whether an SMS fires in addition to or instead of the email for the same trigger. No SMS templates are seeded and no recipient-per-trigger mapping exists. |
| **Why it blocks** | Without the trigger→SMS-recipient list and the additive-vs-replaces rule, we cannot seed SMS templates, wire dispatch call sites (which currently send one email per trigger), or scope the work. A wrong assumption seeds the wrong triggers, targets wrong numbers, or double-notifies. |
| **Question** | **Which specific trigger events should send SMS (vs email only), who is the SMS recipient for each, and does an SMS fire in addition to or instead of that trigger's email? Should the existing dormant `Product.product_purchased_sms_enabled` + phone-number flag become the first live SMS trigger, or do we build a generic engine independent of it?** |
| **Owner** | BA |

> **Scheduling alignment:** the scheduling story already names client-requested scheduled SMS (Workshop Confirmation −24h, product-question SMS), both on deferred event/workshop anchors — useful input to the trigger→SMS list, though not dispatchable until those anchors and the provider land.

#### SMS-07 — Phone-number source & recipient-resolution boundary vs 77.9
| | |
|---|---|
| **Requirement** | "deliver SMS templates to the resolved recipients — Refer User Story Dynamic Receipient Resolution Engine" (story_sources.txt:32-33). SMS recipient resolution is delegated to 77.9. |
| **Codebase reality** | 77.9 defines only EMAIL tokens (`{salesperson}`/`{main customer contact}`/`{all customer contacts}`) and `RecipientList` validates every entry as `IsEmail` (notification-template.dto.ts:81-97) — a phone string cannot be stored. Candidate numbers are scattered: `User.phone` nullable (schema.prisma:16), `Attendee.mobile` required (:779), `Company.billing_phone` nullable, `Order.billing_phone` (:1594), `OnsiteBoothContact.contact_phone` (:2854), Product phone arrays (:1291). No template stores a phone recipient. |
| **The gap** | 76.8 depends on DRR (77.9) for mobile numbers, but 77.9 is email-only and both stories are mutually deferred — a circular dependency. Which entity's phone is the recipient per trigger, and whether SMS reuses `to_recipients` (as phone strings) or a separate field, is undefined. |
| **Why it blocks** | The send path needs a resolved destination number; with no phone-recipient storage and email-only DRR, there is no source. Scoping 76.8 without settling the 77.9 boundary produces an unrunnable integration. |
| **Question** | **How are SMS recipient phone numbers supplied per trigger — is 77.9 (DRR) expanded to resolve mobile numbers, and is the number stored in a new phone-recipient field or reused from `to_recipients`? Confirm 76.8's recipient-resolution boundary vs 77.9 given both are mutually deferred.** |
| **Owner** | BA |

### Major

#### SMS-08 — Sender identity (from-number / sender ID / short-or-long code)
| | |
|---|---|
| **Requirement** | V2 requires routing "SMS dispatch through the integrated provider once configured" (story_sources.txt:69) but never defines the originating identity. |
| **Codebase reality** | Email has an `AllowedFromDomain` whitelist (admin schema.prisma:299-307) and `channel_config.from_address` validated against it (service.ts:251). There is no SMS sender/from-number equivalent anywhere. Controller doc says SMS `channel_config` is read-only (controller.ts:238) and no SMS-oriented keys (sender_id/originating number) were ever defined (evidence:sms §7). |
| **The gap** | The SMS originating identity is undefined — dedicated long code, toll-free number, short code, or alphanumeric sender ID — and where it is stored (global provider config vs per-template `channel_config.sender_id`). It is also provider- and country-registration-dependent (A2P 10DLC / toll-free verification). |
| **Why it blocks** | The from-number/sender registration must be provisioned and chosen before any message can be sent, and it drives whether `channel_config` needs an SMS sender field. A wrong choice affects deliverability, cost, and registration lead time. |
| **Question** | **What sender identity will SMS use (dedicated long code / toll-free / short code / alphanumeric sender ID), is it a single global originator or per-template, and who handles the required carrier registration (A2P 10DLC / toll-free verification)?** |
| **Owner** | Client |

> **Provider update (SendGrid → Twilio SMS):** in the Twilio ecosystem the sender identity is a Messaging Service SID or a provisioned from-number (long code / toll-free / short code) with A2P 10DLC (or toll-free) registration — none provisioned yet. Naming the provider narrows the options but the number and its registration still must be procured.

#### SMS-09 — Delivery-receipt handling, retry & failure policy
| | |
|---|---|
| **Requirement** | "System shall handle the provider's delivery response (success/failure) for each SMS dispatch. (Subject to R&D)" and "Delivery failures must be logged and surfaced for troubleshooting/retry per the defined mechanism. (Subject to R&D)" (story_sources.txt:48, :89, :91). |
| **Codebase reality** | The email send contract never throws and returns `{status:'SENT'\|'FAILED', providerMessageId, error}` synchronously (worker mailer.service.ts:90-184); `NotificationLog` has `status` default PENDING→SENT/FAILED and `retry_count` (admin schema.prisma:317-318) but no async callback path. Zero SMS code. Provider delivery receipts are asynchronous (webhook/callback), which the synchronous email pattern does not support. |
| **The gap** | The mechanism for capturing provider delivery status is undecided — async delivery-receipt webhook vs status polling — as is the retry/failure policy (how many retries, on what errors, PENDING→final transition). All "Subject to R&D," no code or endpoint. |
| **Why it blocks** | A webhook approach requires a new public callback endpoint + provider signature verification + a status-update path, architecturally different from the synchronous email flow. Choosing wrong forces rework of dispatch and log-update design. |
| **Question** | **How should SMS delivery outcomes be captured — an asynchronous provider delivery-receipt webhook (needs a new callback endpoint) or status polling — and what is the retry/failure policy (max retries, retryable error classes, final status transitions)?** |
| **Owner** | BA |

> **Provider update (SendGrid → Twilio SMS):** Twilio Programmable Messaging exposes asynchronous **status-callback webhooks** (`queued → sent → delivered / undelivered / failed`), so the concrete mechanism would be a Twilio status webhook + a new signed callback endpoint — resolving the "webhook vs polling" half of this question; the retry/failure policy still needs defining.

#### SMS-10 — SMS body rendering, length/segmentation & unicode
| | |
|---|---|
| **Requirement** | "System shall use the integrated SMS provider to deliver SMS templates" (story_sources.txt:32); "Placeholders must be resolved to actual values before the SMS is dispatched" (:83). |
| **Codebase reality** | Email bodies are HTML, escaped via `Handlebars.escapeExpression` and wrapped in a branded Handlebars layout shell (`renderWithLayout`, worker mailer.service.ts:197-221); token substitution is literal `split('{{key}}').join(value)` (:236-245). SMS rows force subject + `channel_config` read-only (`assertPredefinedFieldsEditable` branch, notification-template.service.ts:408-415), implying no subject, but there is no plain-text SMS render path and no segmentation logic anywhere. |
| **The gap** | SMS rendering rules are unspecified: confirm SMS skips subject and the HTML/branded layout (plain text only), how the branded shell/asset URLs are excluded, and — critically — how message length, GSM-7 vs unicode encoding, and multi-segment splitting (and its cost multiplier) are handled when a resolved body exceeds one segment. |
| **Why it blocks** | Reusing the email render (HTML + layout) would produce broken, oversized, multi-segment SMS. A separate plain-text render + segmentation strategy must be defined before the send path is written; length limits may also constrain template-body validation. |
| **Question** | **Confirm SMS templates render as plain text with no subject/branded layout, and define the message-length policy: is there a max length / single-segment cap, and how are >160-char (or unicode) messages handled and costed (auto-split vs truncate vs reject)?** |
| **Owner** | BA |

#### SMS-11 — E.164 normalization & invalid/missing-number fallback
| | |
|---|---|
| **Requirement** | "deliver SMS templates to the resolved recipients" (story_sources.txt:32) presupposes deliverable, correctly-formatted numbers. |
| **Codebase reality** | All phone fields are Postgres `VarChar(20)`/`VarChar(50)` with no E.164 normalization at storage (evidence:sms §4). `@IsValidPhone` (is-valid-phone.validator.ts:113-217) calls PhoneValidator.com live, restricts to US/CA, and fails open when `PHONE_VALIDATOR_API_KEY` is missing or the API is down (validation always passes). One seeded logistics number `'+1617555082713'` is malformed (13 digits after +1). |
| **The gap** | Stored numbers are not guaranteed valid or E.164-formatted (fail-open validation, known malformed data). Undefined whether numbers must be normalized/validated to E.164 before send, and what the fallback is when a recipient number is missing, malformed, or non-US/CA. |
| **Why it blocks** | Providers reject non-E.164 numbers; without a normalization + pre-send validation step and a defined fallback (skip+log / default / abort), dispatches will silently fail or error at the provider. This shapes the send-path guard logic. |
| **Question** | **Must recipient numbers be normalized/validated to E.164 before dispatch, and what is the fallback when a number is missing or invalid (skip + log, use a default, or abort the trigger)? Note existing data is fail-open-validated and includes malformed numbers.** |
| **Owner** | BA |

### Minor

#### SMS-12 — International vs US-only reach
| | |
|---|---|
| **Requirement** | V2 does not scope the geographic reach of SMS (story_sources.txt:26-97). |
| **Codebase reality** | `@IsValidPhone` is region-locked to US/Canada (`region=2`) (phone-validation.config.ts / is-valid-phone.validator.ts:113-217). `Attendee.mobile` and other phone fields are free `VarChar` with no country-code guarantee (schema.prisma:779 etc.). |
| **The gap** | Whether SMS must reach only US/Canada numbers or also international recipients is undefined. This affects provider plan/registration, per-country cost, sender-ID rules, and whether the existing US/CA validation is sufficient or must be widened. |
| **Why it blocks** | International reach changes provider selection, compliance, and cost model; assuming US-only when international is needed (or vice versa) forces provisioning and validation rework. |
| **Question** | **Is SMS US/Canada-only (matching the existing phone-validation region lock) or must it support international numbers/country codes? This affects provider plan, cost, and sender registration.** |
| **Owner** | Client |

#### SMS-14 — Rate limits, throttling & sandbox vs prod
| | |
|---|---|
| **Requirement** | "The system must route SMS dispatch through the integrated provider once configured" (story_sources.txt:69); delivery/retry mechanism "Subject to R&D" (:91). |
| **Codebase reality** | No SMS throttling, queue, or rate-limit handling exists (no SMS code at all, evidence:sms §2). The email path sends synchronously with no rate governor. Providers enforce per-second/per-day A2P throughput caps (e.g. 10DLC MPS limits). |
| **The gap** | Provider rate limits / throughput caps and the need for a sandbox-vs-production split are unaddressed. Undefined whether SMS dispatch needs queuing/throttling to respect provider MPS limits, and how a test/sandbox mode is toggled without sending live texts. (Rate limits are provider-derived once SMS-01 is answered; the open decision is whether bulk triggers require a queue and a no-live-send test mode.) |
| **Why it blocks** | Bulk triggers could exceed provider MPS caps and get throttled/blocked without a queue; and without a sandbox toggle, dev/QA risks sending real SMS. Both shape the dispatch architecture and config keys. |
| **Question** | **Do any SMS triggers fire in bulk such that dispatch must be queued/throttled to respect the provider's throughput caps? And is a sandbox vs production mode required (test credentials / no-live-send toggle) for dev and QA?** |
| **Owner** | BA |

---

## Consolidated question checklist

Ready to paste into an email to the client/BA. Each tagged with its owner.

1. **[BA]** Is 76.8 in scope to build actual SMS sending this sprint, or does it remain storage/edit-only (send path stays gated) as agreed on 2026-06-03? If pulled forward, has the provider dependency (Q2) been resolved? *(SMS-02)*
2. **[Client/BA]** Provider named as **SendGrid** — but SendGrid's API is email-only. Confirm SMS is sent via Twilio Programmable Messaging (SendGrid's parent) under the same account (`twilio` SDK + Account SID / Auth Token / Messaging Service), and confirm who provisions/owns that account and the sending number. *(SMS-01)*
3. **[BA]** How do SMS templates come into existence for the send path — seed predefined SMS rows and/or unlock predefined-SMS create (custom SMS stays out of scope)? And define the SMS `channel_config` contract (sender_id / originating number / any segment metadata). *(SMS-15)*
4. **[Client]** What is the SMS consent/opt-in policy (which entity holds consent, is prior express consent required before sending)? Must we persist a suppression list honoring provider-reported opt-outs and enforce TCPA quiet-hours? *(SMS-03)*
5. **[BA]** Should SMS dispatch reuse `NotificationLog` with new `channel` + phone/recipient columns (admin-owned migration, propagated via `db push`), or a separate SMS log table? *(SMS-05)*
6. **[BA]** Where should SMS provider credentials/config live — env + AWS Secrets (mirroring SendGrid), a DB config row, or an admin-managed provider-config screen? If a config UI is exposed, confirm it is Admin-role restricted. *(SMS-04)*
7. **[BA]** Which specific trigger events should send SMS (vs email only), who is the SMS recipient for each, and does an SMS fire in addition to or instead of that trigger's email? Should the dormant `Product.product_purchased_sms_enabled` flag become the first live SMS trigger, or do we build a generic engine? *(SMS-06)*
8. **[BA]** How are SMS recipient phone numbers supplied per trigger — is 77.9 (DRR) expanded to resolve mobile numbers, and is the number stored in a new phone-recipient field or reused from `to_recipients`? Confirm 76.8's boundary vs 77.9 given both are mutually deferred. *(SMS-07)*
9. **[Client]** What sender identity will SMS use (dedicated long code / toll-free / short code / alphanumeric sender ID), is it a single global originator or per-template, and who handles carrier registration (A2P 10DLC / toll-free verification)? *(SMS-08)*
10. **[BA]** How should SMS delivery outcomes be captured — an asynchronous provider delivery-receipt webhook (needs a new callback endpoint) or status polling — and what is the retry/failure policy (max retries, retryable error classes, final status transitions)? *(SMS-09)*
11. **[BA]** Confirm SMS templates render as plain text with no subject/branded layout, and define the message-length policy: is there a max length / single-segment cap, and how are >160-char (or unicode) messages handled and costed (auto-split vs truncate vs reject)? *(SMS-10)*
12. **[BA]** Must recipient numbers be normalized/validated to E.164 before dispatch, and what is the fallback when a number is missing or invalid (skip + log, use a default, or abort the trigger)? *(SMS-11)*
13. **[Client]** Is SMS US/Canada-only (matching the existing phone-validation region lock) or must it support international numbers/country codes? *(SMS-12)*
14. **[BA]** Do any SMS triggers fire in bulk such that dispatch must be queued/throttled to respect the provider's throughput caps? And is a sandbox vs production mode required (test credentials / no-live-send toggle) for dev and QA? *(SMS-14)*

---

## Already settled — not blocking

These were considered during the gap review and dropped as already answered by existing architecture; they do not require client/BA sign-off.

- **SMS-13 — Send-path repo ownership & schema sync.** This is an internal engineering decision, not a BA/client question. The existing architecture already answers it: SMS send naturally mirrors email in `background-worker-service`; the admin repo owns any `NotificationLog` migration and the other repos pick it up via `db push` (the established pattern). Its one substantive fragment — propagating the SMS log-schema change across the db-push repos — is folded into **SMS-05**. Nothing here requires client/BA sign-off.
