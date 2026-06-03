# Email & SMS Management — Effort Justification

**Module:** Admin-panel Email & SMS Notification Management
**Phase covered:** Requirement analysis → schema design → CRUD implementation planning
**Audience:** Sprint review / management update / effort justification
**Prepared:** May 2026

---

## Purpose of this document

This module looks, on the surface, like "build CRUD screens for email templates." The estimate and the actual effort are higher than a naive CRUD feature because the work sits on top of a **shared production database consumed by five services**, reconciles **three conflicting source documents**, and had to absorb **mid-flight client decisions** (SMS, time delays, two-tier ownership) without breaking 14 live notification flows already in production.

The sections below itemize where the effort genuinely went, organized by category, with story-specific observations where they apply. The intent is to make the engineering, analysis, and coordination work visible — not to defend it.

---

## 1. Requirement analysis & source reconciliation

The feature was specified across **three documents that did not agree with each other**, and reconciling them was a prerequisite to writing a single line of schema.

| Source | What it contained | Why it needed work |
|---|---|---|
| `Email & SMS Management.xlsx` | 6 user stories (listing, search, filter, detail, edit/WYSIWYG, recipient config) | Described the *admin experience* but said nothing about which underlying triggers exist or how sends actually happen. |
| `ONLY_Auto_Email_Notification_Triggers.xlsx` | 40 template records (36 Email + 4 SMS) across Store/Internal/Vendor/Product/PPL | This is the client's *desired* catalog — but only a fraction maps to triggers that exist in the codebase today. |
| `SBE_client_feedback_email_sms.pdf` | 7-message thread (May 14–20) between UIPL and the client (Theo/Zach) | The decisions here **overrode** parts of the Excel sheets (e.g., two-tier ownership, FROM-domain restriction, "no admin-created triggers"). |

**Key reconciliation findings that drove design:**

- The client's 40-template catalog and the system's **14 active `sendFromTemplate()` call sites overlap by only ~5**. Treating the Excel as the build list verbatim would have produced 26 templates wired to **triggers that don't exist yet** (Contracts, Cart, Orders, Booth modules are unbuilt). Identifying this gap early is what kept the scope honest and prevented seeding dead configuration.
- The client considers **time-delay scheduling essential** (11+ templates are time-based); UIPL had scoped it out of the current phase. That tension is real and unresolved at the product level — the design had to *store* schedule configuration now without *consuming* it, so the UI can be built once and the scheduler can attach later with no rework.
- **SMS was introduced mid-analysis** (4 SMS templates in the Excel) even though **no SMS provider integration exists**. This forced a channel-agnostic design rather than an email-only one.

This level of cross-document reconciliation is analysis effort that produces no visible code but determines whether the code that follows is correct.

---

## 2. Codebase discovery across five services

The notification system is **not localized to one service**. Before designing, every producer of notifications had to be located and verified, because the schema is shared and a wrong assumption breaks production.

- **Five NestJS backends share one PostgreSQL database.** Only `admin-backend-api` owns migrations; the other four (`exhibitor-backend-api`, `background-worker-service`, `external-api-service`, `pulse-broker-service`) use `db push` only. Any schema change must be safe to `prisma generate` across all five.
- **14 active `sendFromTemplate()` call sites** were located and confirmed by reading the actual literal slug strings at each site, spread across 4 services:
  - admin: `welcome_email`, `forgot_password`, `exhibitor_welcome_admin_created`
  - exhibitor: `welcome_email_exhibitor`, `exhibitor_forgot_password`, `contact_us_acknowledgment`, `contact_us_admin_notification`, `company_user_invitation`, `invitation_accepted_to_exhibitor`
  - background-worker: `lead_assigned_preview`, `lead_daily_summary`, `low_balance_warning`
  - external-api: `ppl_order_confirmation`, `ppl_subscription_renewal`
- **4 dormant trigger slugs** were found seeded but with no caller yet (`lead_claimed_full_details`, `lead_claimed_by_other`, `lead_distribution_expired`, `lead_credits_renewed`). Deciding what to do with these (seed as editable predefined rows vs omit) was a deliberate call, not an oversight.
- **Four independent copies of `MailerService`** exist (one per sending service), all using the same Handlebars + SendGrid pattern against the shared table. This multiplied the backward-compatibility surface — a schema change has to be safe for four consumers written at different times.

Verifying the real producers (rather than trusting the seeder or the Excel) is what made it safe to promise "the 14 live flows keep working."

---

## 3. Architecture & schema design decisions

The schema is the heart of the effort. Several decisions each required weighing trade-offs rather than picking an obvious default.

### 3.1 Single table vs split tables (predefined vs custom)
Confirmed a **single `notification_templates` table with an `is_predefined` flag** rather than two tables. This keeps listing/search/filter queries simple (one source) but pushes the predefined-vs-custom edit rules into the **service layer**, which then had to be specified field-by-field (see §4).

### 3.2 Polymorphic `channel_config` JSONB (the SMS-driven decision)
Rather than six email-shaped columns (`from_address`, `from_name`, `reply_to`, `to/cc/bcc_recipients`), the design folds recipient configuration into a single `channel_config` JSONB whose **shape varies by channel**:
- EMAIL variant: from/reply-to/to/cc/bcc
- SMS variant: `sender_id` + `to_recipients`

**Why this took thought, not just typing:** the obvious email-columns approach would have left every SMS row carrying six NULL email columns, and would have required a schema migration for every future channel (PUSH, WhatsApp). The JSONB approach trades database-level constraints for **service-layer validation**, which then had to be designed per channel (E.164 phone validation, alphanumeric sender ID ≤ 11 chars, domain whitelist for FROM). That validation logic is real work that the column-based approach would have gotten "for free" from the DB — a deliberate trade-off, documented.

### 3.3 `channel` enum promotion
Promoting `channel` from free-form `VarChar(50)` to a Prisma enum `{ EMAIL, SMS }` required: confirming all 18 existing rows are `'EMAIL'` (so `ALTER COLUMN ... USING channel::NotificationChannel` is safe), and **dropping `PUSH`** from the existing DTO whitelist (`NOTIFICATION_CHANNELS`), which in turn means updating existing spec files that pass `'PUSH'`. A one-line type change cascaded into test and DTO changes across the service.

### 3.4 `trigger_events` table + the 1:1 integrity guard
This was the subtlest piece. Requirement: querying by `notification_type` for a predefined trigger must return **exactly one row**, and admins must **not** be able to create triggers. The design:
- `trigger_events` is **strictly code-controlled** (no admin CRUD endpoints).
- An `is_custom` column + **composite unique `(slug, is_custom)`** acts as a structural guard.
- Because the composite doesn't make `slug` alone a valid FK target, a **partial unique index** `ON slug WHERE is_custom = false` was needed so `notification_templates.notification_type` can FK to it.

Getting from "add a flag" to "composite unique + partial unique index to preserve a valid FK target" is exactly the kind of integrity reasoning that prevents silent data-duplication bugs later — and it is not obvious from the requirement text.

### 3.5 Reusing `AdminAuditLog` instead of a new table
Edit history reuses the existing `AdminAuditLog` (adding one enum value `notification_template`) rather than introducing a new audit table. This kept the migration small but required specifying **audit granularity** — one row per changed scalar field, one row per changed top-level `channel_config` key, and the JSONB scheduling arrays logged whole. That specification is design effort that makes the audit trail usable rather than noisy.

### 3.6 Array-shaped `schedule_config` / `follow_up_config`
Both were made **arrays of objects** (multi-shot scheduling / follow-up sequences) and kept **channel-agnostic** so they apply equally to EMAIL and SMS. They are intentionally minimal now ("send immediately" / "no follow-up" when null/empty) so the **UI can be built once** and grow via data migration when the scheduler ships — avoiding a second front-end pass.

---

## 4. Business-rule complexity (service-layer enforcement)

The "edit a template" story is deceptively heavy because the **editable field set depends on both `is_predefined` and `channel`**. This is a 2×2 matrix of rules that had to be enumerated explicitly:

| | EMAIL | SMS |
|---|---|---|
| **Predefined** | Editable: `subject`, `body`, `is_active`, `type`, and `channel_config.{from_name, reply_to, cc, bcc}`. Locked: `notification_type`, `channel`, `from_address`, `to_recipients`. | Editable: `body`, `is_active`, `type` only. **Nothing** inside `channel_config` is editable. |
| **Custom** | Full control; FROM domain must be in `allowed_from_domains`; all email strings validated. | `sender_id` alphanumeric ≤ 11 chars or E.164; `to_recipients` must be E.164. Email-only keys rejected. |

Plus cross-channel rejection (an `from_name` key on an SMS row → 400; `sender_id` on an EMAIL row → 400). Each cell is a distinct validation path with its own test. This is where "CRUD" stops being CRUD.

---

## 5. Edge cases identified through analysis (risks avoided)

Careful upfront analysis surfaced concrete failure modes that would otherwise have been discovered in production:

- **Dead configuration risk:** seeding 26 templates against non-existent triggers would have created FK failures or orphaned, un-fireable rows. Avoided by scoping to 18 real slugs.
- **Production breakage risk:** the `channel` enum migration is a no-op only because all existing rows are `'EMAIL'` — this was verified, not assumed. Had a stray `'PUSH'`/`'SMS'` row existed, the migration would have failed mid-deploy.
- **Silent overwrite / duplicate-trigger risk:** without the `(slug, is_custom)` composite + partial unique index, a future custom trigger could collide with a predefined slug and make the `notification_type` lookup ambiguous.
- **NULL-column sprawl:** the JSONB `channel_config` avoids SMS rows carrying meaningless NULL email columns and avoids a migration per new channel.
- **Cross-service generate failure:** because four other services `prisma generate` off the same schema, the verification plan explicitly checks all of them — a schema change that compiles in admin but breaks the worker would otherwise surface only at the next worker deploy.
- **Backward-compatibility for 14 live flows:** all new columns are nullable and the mailer doesn't read `channel_config` yet, so existing sends are provably unchanged. The verification plan includes a smoke test across registration, password reset, contact-us, a lead-distribution run, and a Stripe test webhook.

Each of these is a bug that did **not** happen because the analysis happened first.

---

## 6. Story-specific observations

| Story | Where the effort concentrated |
|---|---|
| **#1 Listing** | Deciding list columns and that `is_predefined`/`channel`/`type` are first-class filterable columns (not buried in JSONB) so the grid stays query-efficient. |
| **#2 Search** | Scoping searchable fields (`template_name`, `subject`, `notification_type`) and explicitly flagging that searching `body` would need a GIN index — a performance decision, not a default. |
| **#3 Filter** | Five filter dimensions (`type`, `channel`, `is_active`, `is_predefined`, `notification_type`), each mapped to a real column. |
| **#4 Detail view** | Joining `available_placeholders` from `trigger_events` so the detail view can drive the placeholder picker — couples two tables for one screen. |
| **#5 Edit (WYSIWYG)** | The 2×2 edit-rule matrix (§4); plus the still-open WYSIWYG library choice, which affects DTO validation (sanitized HTML vs Markdown) and placeholder integration — flagged as a blocker rather than guessed. |
| **#6 Recipient config** | The entire polymorphic `channel_config` design, FROM-domain whitelist, and channel-specific validation — the single most design-heavy story. |

---

## 7. Cross-team & client communication

- The design absorbed a **live 7-message client thread** (Theo Giovanopoulos, SVP Ops; Zach Lezberg, Founder/CEO) whose decisions overrode the written specs — two-tier ownership, FROM-domain restriction to `TheShowProducers.com` / `TheSmallBusinessExpo.com`, and "no admin-created triggers." Tracking which message superseded which spec was itself coordination work.
- An **unresolved product tension** (time delays: client = essential, UIPL = deferred) was handled by designing for storage-now/consume-later rather than forcing a premature decision — keeping the relationship and the schema both intact.
- **19 open questions** were itemized and severity-tagged (Block / Soft / Defer) so reviewers and the client can resolve blockers before coding, rather than discovering them mid-sprint. Five remain hard blockers (WYSIWYG library, permission slug, soft vs hard delete, whether to seed SMS predefined rows now, sender-ID source for predefined SMS).

---

## 8. Documentation & review effort

Two review artifacts were produced and iterated:
- A **TL-facing design review** (`EMAIL_SMS_DB_DESIGN_REVIEW.md`) with column→requirement traceability, JSONB shape examples, enum summary, and migration ordering.
- A **full CRUD design plan** with requirements traceability back to all three source documents, a 14-step verification checklist, and the gaps register.

Traceability tables that map *every* column and decision back to a specific user story or client message are what let a reviewer approve the design quickly and what let the client see their requests reflected — that mapping is deliberate documentation work.

---

## 9. Why upfront understanding was necessary before implementation

Pulling the threads together, implementation could not safely start earlier because:

1. **The build list wasn't in the requirements** — it had to be *derived* by intersecting the client's 40-template wish-list with the 14 real triggers in code. Coding against the Excel verbatim would have built 26 broken templates.
2. **The schema is shared and live** — a wrong column type or a missing nullable would break four other services and 14 production flows. The "verify, don't assume" discipline (enum migration safety, cross-service generate) is the cost of working on a shared production DB.
3. **Requirements were still moving** — SMS and the two-tier model arrived mid-analysis. A channel-agnostic, JSONB-based design was chosen *specifically* so that the late additions didn't force a redesign.
4. **The integrity rules are non-obvious** — the 1:1 trigger↔template guarantee needed a composite unique plus a partial unique index; the edit rules are a 2×2 matrix. Discovering these after coding would have meant rework plus a data migration.

The time spent understanding and validating is what converted a feature that *looks* like CRUD into one that is **safe to ship on a shared production database serving five services**, with no rework expected when the deferred scheduler, SMS provider, and mailer work attach to the configuration this phase puts in place.
