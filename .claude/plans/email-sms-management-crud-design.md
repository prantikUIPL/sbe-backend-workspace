# Email & SMS Management — CRUD Design Document

> **Status**: Design under review. CRUD-only scope. Basis is the **V2 two-epic backlog** (`76.x Predefined` — edit-only, Email + SMS; `77.x Custom` — full CRUD, **Email only**). Mailer/scheduler/SMS-provider work is deferred to follow-on plans.

## Context

Sources of truth analyzed:
- **"Email & SMS Management.xlsx"** — original 6 user stories (V1: listing, search, filter, detail view, edit, recipient config). Retained as historical baseline; **superseded by V2 below.**
- **"ONLY_Auto_Email_Notification_Triggers.xlsx"** — 40 template records (36 Email + 4 SMS) across Store/Internal/Vendor/PPL/Product types
- **"SBE_client_feedback_email_sms.pdf"** — May 14–20 email thread between UIPL (Amrin) and client (Theo/Zach)
- **"Email & SMS Management V2.xlsx" / "Email & SMS Management Upadated Epic.xlsx"** — the **current backlog**, restructured into **two epics**: `76.x Predefined Email & SMS Management` (edit-only; Email + SMS) and `77.x Custom Email Management` (full CRUD; **Email only**), ~19 full-text stories. Separate UIs / separate CRUD screens but the **same API endpoints** (service branches on `is_predefined`). The two-tier design here is reused as-is. Story-by-story verdicts and the V1→V2 change log live in `EMAIL_SMS_STORY_REVISIONS_V2.md`.

## Scope: CRUD Only

This plan covers **only the admin-panel CRUD** for notification templates. It is the minimum that gives admins the listing, search, filter, detail view, and edit experience described in the user stories.

**Two epics (V2 backlog):**
- **`76.x` Predefined Email & SMS Management** — system-seeded templates; **edit-only** (no create/delete via API); covers **both Email and SMS**. `trigger_event` / `channel` / `FROM` / `sender_id` / `TO` are read-only; `subject`/`body`/`is_active`/`tag` + EMAIL `channel_config` niceties are editable.
- **`77.x` Custom Email Management** — admin-created templates; **full CRUD**; **Email only** (no custom SMS this sprint — see §Scope note below).
- Predefined and custom are shown as **separate UIs / CRUD screens** but use the **same API endpoints**; the service branches on the `is_predefined` flag. The two-tier rules are enforced in the service layer.

**What's included:**
- Schema evolution: add columns + 2 new supporting tables (reuse existing `AdminAuditLog` for audit)
- Seed 18 in-scope templates as predefined entries (matches the existing `notification-template.seeder.ts`)
- Enhanced CRUD APIs with predefined/custom distinction
- Audit trail on edits via existing `AdminAuditLog`

**What's explicitly out of scope (deferred to later phases, not in this plan):**
- ❌ Mailer changes (CC/BCC/variable FROM in `sendFromTemplate()`) — actual email sending continues to use the existing codepath; new schema fields are stored but not read by the mailer
- ❌ Job scheduling for time-delay templates
- ❌ SMS provider integration
- ❌ Dynamic recipient resolution (`{salesperson_email_address}` etc. at send time)
- ❌ Module-specific triggers (Contracts, Cart, Orders, Booth, etc.)
- ❌ Seeding the 26 templates from the Excel that depend on unbuilt modules
- ❌ **Custom SMS templates** — V2's `77.x` Custom epic is **Email only**. The schema (`NotificationChannel.SMS` + the SMS `channel_config` variant) still supports SMS for **predefined** rows (`76.x`) and keeps custom SMS a zero-migration add later, but custom create/edit is Email-only this sprint (see `EMAIL_SMS_KNOWN_ISSUES.md`)

The admin panel becomes a **configuration store** — admins can edit everything the client requested, and the configuration sits in the database ready for the mailer/scheduler/SMS work to consume it in subsequent plans.

## The 18 In-Scope Templates

All 18 slugs already exist in `notification-template.seeder.ts` today. 14 have an active `sendFromTemplate()` caller; 4 are pre-staged PPL lead-distribution triggers whose worker code hasn't been written yet — admins can still edit the copy via the panel ahead of those workers shipping.

| # | notification_type | Service / Status | In Client Excel? |
|---|---|---|---|
| 1 | welcome_email | admin-backend-api | Yes (#1) |
| 2 | forgot_password | admin-backend-api | Yes (#2) |
| 3 | exhibitor_welcome_admin_created | admin-backend-api | Yes (#1 variant) |
| 4 | welcome_email_exhibitor | exhibitor-backend-api | Yes (#1) |
| 5 | exhibitor_forgot_password | exhibitor-backend-api | Yes (#2) |
| 6 | contact_us_acknowledgment | exhibitor-backend-api | No (system) |
| 7 | contact_us_admin_notification | exhibitor-backend-api | No (system) |
| 8 | company_user_invitation | exhibitor-backend-api | Yes (#3) |
| 9 | invitation_accepted_to_exhibitor | exhibitor-backend-api | No (system) |
| 10 | lead_assigned_preview | background-worker-service | No (PPL) |
| 11 | lead_daily_summary | background-worker-service | No (PPL) |
| 12 | low_balance_warning | background-worker-service | No (PPL) |
| 13 | ppl_order_confirmation | external-api-service | No (PPL) |
| 14 | ppl_subscription_renewal | external-api-service | No (PPL) |
| 15 | lead_claimed_full_details | DORMANT — no caller yet (PPL) | No (PPL) |
| 16 | lead_claimed_by_other | DORMANT — no caller yet (PPL) | No (PPL) |
| 17 | lead_distribution_expired | DORMANT — no caller yet (PPL) | No (PPL) |
| 18 | lead_credits_renewed | DORMANT — no caller yet (PPL) | No (PPL) |

## Design Decisions (Confirmed)

- **Single `notification_templates` table** with `is_predefined` boolean flag — predefined and admin-created custom templates share the same schema
- **Channel**: column is promoted from free-form `VarChar(50)` to Prisma enum `NotificationChannel { EMAIL, SMS }`. The codebase already soft-validates this whitelist at the DTO layer (`NOTIFICATION_CHANNELS = ['EMAIL', 'SMS', 'PUSH']` in `notification-template.dto.ts`); we're moving the constraint into the database and dropping `PUSH` since it has no concrete requirement yet. PUSH can be added to the enum later when scoped.
- **Channel-specific config**: a single `channel_config` JSONB column replaces the six email-shaped columns (`from_address`, `from_name`, `reply_to`, `to_recipients`, `cc_recipients`, `bcc_recipients`). Shape varies by `channel` — see "JSONB shapes" section below. SMS rows don't carry NULL email columns; future channels (PUSH, WhatsApp) add new shape variants without schema migrations.
- **Predefined templates** (the 18 above):
  - Editable across both channels: `subject` (EMAIL only — already nullable for SMS), `body`, `is_active`, `tag`
  - Editable inside `channel_config`:
    - EMAIL: `from_name`, `reply_to`, `cc_recipients`, `bcc_recipients`
    - SMS: (none — predefined SMS has no admin-editable channel config; `body` is the only thing to edit)
  - System-controlled (absent / null) on predefined:
    - EMAIL: `from_address`, `to_recipients`
    - SMS: `sender_id`, `to_recipients`
  - `notification_type` is set by the seeder and links to `trigger_events.slug` via FK (read-only)
- **Custom templates** (admin-created):
  - Full CRUD on `channel_config` for whichever channel the row is
  - EMAIL: FROM email's domain part restricted to TheShowProducers.com or TheSmallBusinessExpo.com via `allowed_from_domains` lookup; local part is free-form
  - SMS: `sender_id` is alphanumeric (≤ 11 chars) **or** E.164 phone (`+1...`); `to_recipients` are E.164 phone strings
  - Admin picks the trigger from the `trigger_events` dropdown → sets `notification_type` to the trigger's slug
  - Multiple templates (predefined + custom) can share the same `notification_type` / trigger; channel is independent of trigger (the same trigger can fire both EMAIL and SMS templates if both exist)
- **Trigger events**: stored in `trigger_events` table; **strictly code-controlled** — admins cannot create, edit, or delete triggers via the admin panel. All seeded rows (20 — see seed count note under "New tables") have `is_custom = false`. `slug` is **globally unique** and is the FK target for `notification_templates.notification_type`; the `is_custom` flag marks the predefined set explicitly. *(Amended 2026-06-11: the earlier composite-unique `(slug, is_custom)` + partial-index FK design was not implementable — Postgres FKs cannot reference partial unique indexes.)*
- **Placeholders**: per-trigger picker, code-maintained (not admin-editable); same placeholder set works across EMAIL and SMS for the same trigger
- **Scheduling**: `schedule_config` and `follow_up_config` are **channel-agnostic** — same JSONB shapes apply whether the row's channel is EMAIL or SMS

## Schema Diagram

```
┌──────────────────────────────────────────────────────────┐
│  notification_templates  (existing, extended)            │
├──────────────────────────────────────────────────────────┤
│  id (PK)                                                 │
│  notification_type ──────┐  ◄── FK to                    │
│                          │      trigger_events.slug      │
│  channel              ◄── enum NotificationChannel       │
│                          {EMAIL, SMS}                    │
│  subject              ◄── nullable (NULL for SMS rows)   │
│  body, language                                          │
│  is_active, created_at, updated_at                       │
│  ─── NEW COLUMNS (6) ───────────────────────────────────│
│  template_name                                           │
│  tag                 ◄── enum NotificationTemplateType   │
│  channel_config (JSONB) ◄── shape varies by channel      │
│                             (see EMAIL/SMS examples)     │
│  is_predefined       (boolean)                           │
│  schedule_config (JSONB)  (array; channel-agnostic;      │
│                            stored, not consumed)         │
│  follow_up_config (JSONB) (array; channel-agnostic;      │
│                            stored, not consumed)         │
└──────────────────────┬───────────────────────────────────┘
                       │
                       │ N
                       ▼
            ┌──────────────────┐         ┌───────────────────┐
            │  trigger_events  │         │ admin_audit_logs  │
            │  (NEW, 20 rows)  │         │  (existing)       │
            ├──────────────────┤         ├───────────────────┤
            │  id (PK)         │         │  id (PK)          │
            │  slug (UNIQUE)   │         │  entity_type      │
            │   ◄── FK target  │         │   = 'notification_│
            │  label           │         │     template'     │
            │  available_      │         │  entity_id ──────►│ notification
            │   placeholders   │         │                   │ _templates.id
            │   (JSONB)        │         │  previous_value   │ (logical, no FK)
            │  is_custom       │         │  new_value        │
            │   (boolean flag, │         │  performed_by ───►│ users.id
            │   all seeded     │         │  note             │
            │   rows = false)  │         │  created_at       │
            └──────────────────┘         └───────────────────┘

┌────────────────────────────┐
│ allowed_from_domains       │  ← Service-layer lookup only;
│  (NEW, 2 rows seeded)      │    no FK from notification_templates
├────────────────────────────┤
│  id (PK)                   │
│  domain (unique)           │
│  is_active                 │
└────────────────────────────┘
```

### Enum summary

| Enum | Status | Values |
|---|---|---|
| `NotificationChannel` | NEW | `EMAIL`, `SMS` |
| `NotificationTemplateType` | NEW | `Store`, `Internal`, `Vendor`, `Product`, `PPL`, `System` |
| `AdminAuditEntityType` | existing, +1 value | `... + notification_template` |

## Schema Changes

### Existing table extensions

`notification_templates` — add columns:

| Column | Type | Notes |
|---|---|---|
| `template_name` | varchar | Human-readable display name |
| `tag` | enum `NotificationTemplateType` | Store/Internal/Vendor/Product/PPL/System (filterable); column renamed from `type`, enum name unchanged |
| `channel` | enum `NotificationChannel` | CHANGED — column type promoted from `VarChar(50)` to enum `{ EMAIL, SMS }`; UI labels this "Format" |
| `channel_config` | JSONB | nullable; **shape varies by `channel`** (see below); replaces 6 email-only columns (`from_address`, `from_name`, `reply_to`, `to_recipients`, `cc_recipients`, `bcc_recipients`) |
| `is_predefined` | boolean | default false; the 18 seeded rows are true |
| `schedule_config` | JSONB | nullable; **minimal shape** (see below); channel-agnostic; stored but not consumed by any worker in this plan |
| `follow_up_config` | JSONB | nullable; **minimal shape** (see below); channel-agnostic; stored but not consumed by any worker in this plan |
| ~~`trigger_event_id`~~ | — | DROPPED — `notification_type` itself is now a FK to `trigger_events.slug`; no separate FK column needed |
| ~~`format`~~ | — | DROPPED — reuse existing `channel` column, UI labels it "Format" |
| ~~`from_address`, `from_name`, `reply_to`, `to_recipients`, `cc_recipients`, `bcc_recipients`~~ | — | DROPPED — folded into `channel_config` JSONB so SMS rows don't carry NULL email columns and new channels (PUSH, WhatsApp) won't need schema migrations |
| ~~`updated_by`~~ | — | DROPPED — "who edited this" is already captured by `admin_audit_logs.performed_by`, no need to duplicate on the template row |

### New tables

**`trigger_events`**
- `id` (PK)
- `slug` — matches `notification_type` for predefined templates
- `label`
- `available_placeholders` (JSONB) — list of placeholder slugs valid for this trigger
- `is_custom` (boolean, default `false`) — flag column. All seeded rows have `is_custom = false`. Admins **cannot** create custom triggers via the admin panel in this plan; the column exists to make the "predefined" set explicit at query time.
- **Unique constraint** *(amended at implementation, 2026-06-11)*: `slug` is **globally unique** (`@unique`). The earlier composite-unique `(slug, is_custom)` + partial-index design was dropped — **Postgres foreign keys cannot reference a partial unique index**, so it was not implementable as specified. Global uniqueness preserves the 1:1 predefined-trigger ↔ slug mapping and lets the FK + relation be declared natively in Prisma across all 5 service schemas (safe under `db push`, zero raw-SQL-only objects). Trade-off: a future *custom* trigger cannot reuse a predefined slug — custom triggers must use distinct slugs. See `EMAIL_SMS_KNOWN_ISSUES.md` #13.
- **FK note**: `notification_templates.notification_type` is a plain foreign key to `trigger_events.slug` (`ON DELETE RESTRICT ON UPDATE CASCADE`), declared as a Prisma relation.
- **Seed count note**: the seeder ships **20** trigger rows, not 18 — the existing template seeder also contains `ppl_subscription_canceled` and `ppl_product_order_payment`, and the FK requires a trigger row for **every** existing `notification_type`. The Email & SMS Management admin UI scope remains the 18 in-scope templates.
- Note: `tag` is intentionally **not** stored here. Trigger and tag are decoupled — admin picks them independently when creating a custom template.

**`NotificationTemplateType` enum** (Prisma enum, follows existing `AdminAuditEntityType` pattern)
- Values: `Store`, `Internal`, `Vendor`, `Product`, `PPL`, `System`
- Used by `notification_templates.tag` column for strict typing

**`NotificationChannel` enum** (Prisma enum)
- Values: `EMAIL`, `SMS`
- Promoted from the free-form `VarChar(50)` column. Migration: `ALTER COLUMN channel TYPE NotificationChannel USING channel::NotificationChannel` (all 18 existing rows are `'EMAIL'`, conversion is safe)
- Update existing tests in `notification-template.controller.spec.ts` / `notification-template.service.spec.ts` that pass `'PUSH'` as a channel value — PUSH is removed from the whitelist in this plan; tests should be updated to either use SMS or be marked TODO until PUSH is scoped
- Update `NOTIFICATION_CHANNELS` constant in `notification-template.dto.ts` to drop `'PUSH'`

### JSONB shapes

#### `channel_config` — varies by `channel`

The shape is validated in the service layer based on the row's `channel` value. Predefined rows leave system-controlled keys absent or null; custom rows must populate them.

**`channel = EMAIL`**
```json
{
  "from_address":   "sales@theshowproducers.com",
  "from_name":      "Small Business Expo",
  "reply_to":       "support@thesmallbusinessexpo.com",
  "to_recipients":  ["user@example.com"],
  "cc_recipients":  ["copies@example.com"],
  "bcc_recipients": []
}
```
- Predefined: `from_address` and `to_recipients` absent/null (system-controlled, resolved by the calling code at send time)
- Predefined editable: `from_name`, `reply_to`, `cc_recipients`, `bcc_recipients`
- Custom: full control; `from_address` domain must exist in `allowed_from_domains WHERE is_active = true`; all email strings validated

**`channel = SMS`**
```json
{
  "sender_id":     "SBE",
  "to_recipients": ["+15551234567"]
}
```
- Predefined: `sender_id` and `to_recipients` absent/null (system-controlled). Nothing inside `channel_config` is admin-editable for predefined SMS; only `body` and `is_active` are editable on the row itself.
- Custom: `sender_id` is alphanumeric (≤ 11 chars) **or** E.164 phone (`+1...`); `to_recipients` are E.164 phone strings (`+[1-9]\d{1,14}`)
- Email-only keys (`from_name`, `reply_to`, `cc_recipients`, `bcc_recipients`) are rejected by the service layer for SMS rows

Adding future channels (PUSH, WhatsApp) requires only a new shape variant + a new validator; no schema migration.

#### `schedule_config` — array of scheduled sends, channel-agnostic

(to be redefined when the scheduler worker is designed)

Each array entry = one scheduled send of this template after the trigger fires. Multiple entries enable multi-shot scheduling at different delays from the same trigger.

```json
[
  {
    "delay_value": 24,
    "delay_unit": "minutes" | "hours" | "days",
    "timezone": "America/New_York"
  }
]
```

UI per entry: number input + unit dropdown + timezone picker (3 fields). Form supports "Add another schedule" / "Remove" buttons. `null` or `[]` means "send immediately on trigger" (today's behavior — also the default for all 18 seeded rows). Validation: array of objects; each entry's `delay_value` is a non-negative integer; `delay_unit` is one of the three allowed values; `timezone` is a valid IANA zone. Applies identically to EMAIL and SMS rows.

#### `follow_up_config` — array of follow-ups, channel-agnostic

(to be redefined when the follow-up worker is designed)

Each array entry = one follow-up send after the initial send. Multiple entries form a sequence (e.g., remind at +1d, +3d, +7d).

```json
[
  {
    "delay_value": 3,
    "delay_unit": "hours" | "days"
  }
]
```

UI per entry: number input + unit dropdown (2 fields). Form supports "Add another follow-up" / "Remove" buttons. `null` or `[]` means "no follow-up". Sequence order in the array determines send order. Stop conditions and per-step follow-up template references are deferred to the scheduler plan — when that lands, each step can grow to `{ delay_value, delay_unit, template_id, stop_if }` via data migration. Applies identically to EMAIL and SMS rows.

**`allowed_from_domains`** (simplified from previous design)
- `id`, `domain`, `is_active`
- Seeded with the two allowed domains: `theshowproducers.com`, `thesmallbusinessexpo.com`
- Only the domain part is constrained; admins enter any local part (e.g., `sales@theshowproducers.com`, `events@thesmallbusinessexpo.com`)
- Validation: extract domain from submitted email, check it exists in `allowed_from_domains WHERE is_active = true`

**Audit logging — reuse existing `AdminAuditLog`**
- The schema already has `AdminAuditLog` with shape: `entity_type` (enum), `entity_id`, `previous_value`, `new_value`, `performed_by`, `note`, `created_at`
- Used today for: configuration, ppl_setting, role_permission, show_management, etc.
- **Add `notification_template` to the `AdminAuditEntityType` enum** (Prisma migration adds one enum value)
- Service writes one row per changed field with `previous_value` and `new_value`, `note` describing the change ("Updated CC recipients on Contract Sent"), `performed_by` from JWT

## Requirements Traceability

### Source 1: `Email & SMS Management.xlsx` — 6 user stories → schema/API mapping

| # | User story | Schema / API element |
|---|---|---|
| 1 | Listing | `GET /notification-templates` (paginated); list columns sourced from `template_name`, `notification_type`, `tag`, `channel`, `is_active`, `is_predefined`, `updated_at` |
| 2 | Search | `GET /notification-templates?search=...` — searches `template_name`, `subject`, `notification_type` (case-insensitive substring) |
| 3 | Filter | Query params: `?tag=`, `?channel=`, `?is_active=`, `?is_predefined=`, `?notification_type=` |
| 4 | Detail view | `GET /notification-templates/:id` — returns full row + `available_placeholders` joined from `trigger_events` |
| 5 | Edit (WYSIWYG) | `PUT /notification-templates/:id` → `body` column (HTML for EMAIL, plain for SMS) + placeholder picker driven by `trigger_events.available_placeholders` |
| 6 | Recipient config | `channel_config` JSONB — keys `from_address`/`to_recipients`/`cc_recipients`/`bcc_recipients` (EMAIL) or `sender_id`/`to_recipients` (SMS); `allowed_from_domains` lookup for FROM validation |

### Source 2: `ONLY_Auto_Email_Notification_Triggers.xlsx` — 40 templates → schema mapping

| Dimension in Excel | Count | Schema element that represents it |
|---|---|---|
| Type = Store | 18 | `NotificationTemplateType.Store` |
| Type = Internal | 6 | `NotificationTemplateType.Internal` |
| Type = Vendor | 5 | `NotificationTemplateType.Vendor` |
| Type = Product | 10 | `NotificationTemplateType.Product` |
| Type = PPL | 1 | `NotificationTemplateType.PPL` |
| (System templates not in Excel) | n/a | `NotificationTemplateType.System` |
| Channel = EMAIL | 36 | `NotificationChannel.EMAIL` |
| Channel = SMS | 4 | `NotificationChannel.SMS` |
| Time-based triggers (delay after event) | 11+ | `schedule_config` JSONB array (stored, not consumed in this plan) |
| Follow-up triggers | a few | `follow_up_config` JSONB array (stored, not consumed in this plan) |
| Triggers tied to modules not yet built (Contracts, Cart, Orders, Booth) | 26 | **Out of scope** — these 26 do not get seeded in this plan; the 18 seeded slugs cover only existing/wired/staged trigger events |
| Dynamic recipient resolution (e.g., `{salesperson_email_address}`) | several | **Out of scope** — `to_recipients` stores literal email addresses today; resolution at send time is deferred to the mailer plan |

### Source 3: `SBE_client_feedback_email_sms.pdf` — confirmed decisions → schema mapping

| # | Client decision | Schema / API element |
|---|---|---|
| 1 | Single table for predefined + custom | `notification_templates` + `is_predefined` boolean |
| 2 | Predefined: trigger / from / to are read-only | Service-layer reject on `notification_type`, `channel`, `channel_config.from_address`, `channel_config.to_recipients`, `channel_config.sender_id` |
| 3 | Predefined: subject / body / status / cc / bcc editable | Service-layer allow list on `subject`, `body`, `is_active`, `tag`, `channel_config.from_name`, `reply_to`, `cc_recipients`, `bcc_recipients` |
| 4 | Custom: full CRUD, FROM domain-restricted to TheShowProducers.com / TheSmallBusinessExpo.com | `allowed_from_domains` table seeded with the two domains; service-layer domain extraction + validation |
| 5 | Trigger events read-only; new types cannot be created via admin | `trigger_events` table; no POST endpoint for triggers; `notification_type` is a FK to `trigger_events.slug` |
| 6 | Placeholders controlled by code, not editable | `trigger_events.available_placeholders` JSONB (seeded from code, not exposed via admin write APIs) |
| 7 | Time delays (client: essential / UIPL: deferred) | `schedule_config` (array) + `follow_up_config` (array) stored on the row but not consumed by any worker in this plan — shape is admin-fillable, the scheduler plan picks it up later |
| 8 | SMS (4 templates) but no SMS provider yet | `NotificationChannel.SMS` enum value + `channel_config` SMS variant; admin can manage SMS templates today; sending is gated until the SMS-provider plan ships |

### Source 4: `Email & SMS Management V2.xlsx` (two-epic backlog) → story → schema/API mapping

The current backlog (supersedes the V1 6-story spec in Source 1). Per-story verdicts and the V1→V2 change log are in `EMAIL_SMS_STORY_REVISIONS_V2.md`; deferrals are tracked in `EMAIL_SMS_KNOWN_ISSUES.md`.

**Epic `76.x` — Predefined Email & SMS Management (edit-only; Email + SMS)**

| Story | In scope | Schema / API element |
|---|---|---|
| 76.1 Listing | Yes | `GET /notification-templates`; list cols `template_name`, `notification_type`, `tag`, `channel`, `is_active`, `updated_at`; "last modified by/date" **derived from `admin_audit_logs`** (no `updated_by` column) — never-edited rows show *System / Seed* or blank |
| 76.2 Search | Yes | `?search=` over `template_name` + `notification_type` (optionally `subject`) |
| 76.3 Filter | Yes | `?tag=` (uses `System`, **not `Event`** — known-issues #5), `?channel=` (`EMAIL\|SMS`, **`Both` dropped**), `?is_active=` |
| 76.4 Detail View | Yes | `GET /:id`; predefined `FROM`/`TO`/`sender_id` shown **read-only (system-managed)**; scheduling section labelled later-phase |
| 76.5 Edit | Yes | `PUT /:id` two-tier matrix; editable `subject`(EMAIL)/`body`/`is_active`/`tag` + EMAIL `channel_config.{from_name,reply_to,cc_recipients,bcc_recipients}`; CC/BCC from predefined list (no manual free-text for predefined); WYSIWYG stores **HTML body only** |
| 76.6 Scheduling | **Deferred** | `schedule_config`/`follow_up_config` kept nullable, no writer (known-issues #1); zero schema change |
| 76.7 Placeholders | Yes | `trigger_events.available_placeholders` (code-controlled picker) |
| 76.8 SMS provider | **Deferred** | client dependency (known-issues #2); SMS rows still stored/edited, sending gated |
| 76.9 Audit Log | Yes | `GET /:id/audit-logs` over `admin_audit_logs`; "by user" derived |

**Epic `77.x` — Custom Email Management (full CRUD; Email only)**

| Story | In scope | Schema / API element |
|---|---|---|
| 77.1 Create | Yes (Email only) | `POST /notification-templates` with `channel = EMAIL`; FROM = free-text local part + **fixed-domain dropdown** validated against `allowed_from_domains`; TO/CC/BCC from predefined list **or** manual free-text; WYSIWYG stores HTML body only |
| 77.2 Listing | Yes | custom listing **drops the Channel column** (all Email): `template_name`, `tag`, `notification_type`, `is_active` |
| 77.3 Search | Yes | `?search=` over `template_name` + `notification_type` |
| 77.4 Filter | Yes | `?tag=` (`System`); **no Channel filter** (Email-only); `?is_active=` |
| 77.5 Detail View | Yes | `GET /:id`; subject always present (Email) |
| 77.6 Edit | Yes | `PUT /:id` mirrors 77.1 field rules; full edit |
| 77.7 Placeholders | Yes | code-controlled picker (same as 76.7) |
| 77.8 Scheduling | **Deferred** | same as 76.6; zero schema change |
| 77.9 Dynamic Recipient Resolution | **Deferred** | `to_recipients` stores literal strings/tokens now; send-time resolution later (known-issues #3); zero schema change |
| 77.10 Audit Log | Yes | same as 76.9 |

> **Custom SMS is out of scope** — `77.x` is Email-only. The SMS `channel_config` variant and `NotificationChannel.SMS` remain in the schema for `76.x` predefined SMS and a zero-migration future custom-SMS add (known-issues entry).

## CRUD Endpoints

All under `/admin/notification-templates`. Granular permissions reuse the existing authorization pattern.

### Templates

| Method | Path | Purpose |
|---|---|---|
| GET | `/notification-templates` | List with pagination, search, filters (tag, channel, is_active, is_predefined, notification_type) |
| GET | `/notification-templates/:id` | Detail with full config + placeholder list for its trigger event |
| POST | `/notification-templates` | Create **custom Email** template only (predefined cannot be created via API; **custom SMS is out of scope this sprint** — V2 `77.x` is Email-only, so `channel = SMS` is rejected on custom create) |
| PUT | `/notification-templates/:id` | Update with predefined/custom edit rules enforced in service layer |
| DELETE | `/notification-templates/:id` | Delete **custom** template only (predefined cannot be deleted) |

### Supporting endpoints (read-only)

| Method | Path | Purpose |
|---|---|---|
| GET | `/notification-templates/trigger-events` | List trigger events for dropdown |
| GET | `/notification-templates/allowed-from-domains` | List allowed FROM domains (for client-side validation hint) |
| GET | `/notification-templates/:id/audit-logs` | Edit history (queries `admin_audit_logs` where `entity_type = 'notification_template'` and `entity_id = :id`) |

### Service-layer enforcement

- **Predefined edit** (`PUT` with `is_predefined = true`):
  - Reject changes to `notification_type`, `channel`, and the system-controlled keys inside `channel_config` (`from_address`/`to_recipients` for EMAIL; `sender_id`/`to_recipients` for SMS)
  - Allow row-level: `subject` (EMAIL only), `body`, `is_active`, `tag`
  - Allow inside `channel_config` (EMAIL): `from_name`, `reply_to`, `cc_recipients`, `bcc_recipients`
  - Allow inside `channel_config` (SMS): nothing (predefined SMS has no editable channel config)
- **Custom edit/create** — **Email only this sprint** (V2 `77.x`): reject `channel = SMS` on custom create with 400. Validate `channel_config` against the row's `channel`:
  - EMAIL: extract domain from `from_address`, validate it exists in `allowed_from_domains WHERE is_active = true`; validate `to/cc/bcc` are well-formed email strings
  - SMS: the SMS `channel_config` validation (`sender_id` alphanumeric ≤ 11 chars or E.164; `to_recipients` E.164) **is retained in the validator** for **predefined SMS** rows (`76.x`) and a future custom-SMS add, but is **not reachable via custom create** while custom is Email-only
  - Reject any keys not in the channel's allowed key set (e.g., `from_name` on an SMS row → 400)
  - FK on `notification_type` → `trigger_events.slug` is enforced by the database
- **Audit**: on every successful update, diff old vs new and insert audit rows (`entity_type = 'notification_template'`, `entity_id = template.id`, `performed_by` from JWT):
  - One row per changed scalar field (e.g., `subject`, `body`, `is_active`, `tag`)
  - One row per changed top-level key inside `channel_config` (e.g., changing `channel_config.from_name` produces one audit row reflecting only that key)
  - One row for any change to `schedule_config` as a whole (the array is logged as a single field — `previous_value` and `new_value` hold the full JSON array) — keeps audit simple for array reshuffles/inserts/deletes
  - One row for any change to `follow_up_config` as a whole (same rule as `schedule_config`)

## Critical Files

| File | Change |
|---|---|
| `admin-backend-api/prisma/schema.prisma` | ✅ DONE (2026-06-11): columns added to `NotificationTemplate` (`template_name`, `tag` — both **required**, `channel_config`, `is_predefined`, `schedule_config`, `follow_up_config`); `channel` promoted to `NotificationChannel` enum; new enums + models `TriggerEvent`, `AllowedFromDomain`; `notification_template` added to `AdminAuditEntityType`; **id PKs are `Int`** (`notification_templates.id` converted BigInt→Int, `notification_logs.notification_template_id` follows) |
| `admin-backend-api/prisma/migrations/20260611120000_sbe671_email_sms_management/` | ✅ DONE: hand-authored migration (enums, id conversion, channel promotion, new columns + backfill + NOT NULL, new tables, FK) |
| `admin-backend-api/src/database/seeds/` | ✅ DONE: all 20 seeded templates get `is_predefined = true`, `template_name`, `tag` (via `TEMPLATE_META`); new `trigger-event.seeder.ts` (20 slugs, runs **before** the template seeder — FK) and `allowed-from-domain.seeder.ts` (2 rows) |
| `admin-backend-api/src/admin/notification-template/notification-template.service.ts` | Enhanced CRUD with predefined/custom rules + audit logging |
| `admin-backend-api/src/admin/notification-template/notification-template.controller.ts` | New filter/search query params + trigger events + allowed FROM domains + audit endpoints |
| `admin-backend-api/src/admin/notification-template/dto/notification-template.dto.ts` | Expanded DTOs; separate Create (custom only) and Update (predefined vs custom) DTOs; drop `'PUSH'` from `NOTIFICATION_CHANNELS`; type `channel_config` as a discriminated union over `channel` |
| `admin-backend-api/src/admin/notification-template/notification-template.controller.spec.ts` | Remove/update `'PUSH'` channel test cases; PUSH no longer accepted |
| `admin-backend-api/src/admin/notification-template/notification-template.service.spec.ts` | Same — PUSH removed |

## Verification

1. **Migration**: the hand-authored migration (`20260611120000_sbe671_email_sms_management`) replays cleanly via `migrate reset` / `migrate deploy` in admin-backend-api ✅ *(verified 2026-06-11)*
2. **Prisma generate**: `npx prisma generate` succeeds in all 4 other services (schemas mirrored; they do **not** run `db push` for this change) ✅
3. **Seeding**: seeders upsert exactly 20 predefined templates + 20 trigger events (all with `is_custom = false`) + 2 allowed FROM domains — 20 not 18: the template seeder also contains `ppl_subscription_canceled` and `ppl_product_order_payment`, which the FK requires trigger rows for ✅
4. **Coverage check**: every seeded `notification_type` slug has exactly one predefined row with a matching `trigger_events.slug` (FK constraint passes); the 4 dormant slugs (`lead_claimed_full_details`, `lead_claimed_by_other`, `lead_distribution_expired`, `lead_credits_renewed`) seed cleanly even though no `sendFromTemplate()` caller exists yet ✅
5. **List API**: `GET /notification-templates` supports search, type filter, format filter, is_active filter, is_predefined filter
6. **Detail API**: `GET /notification-templates/:id` returns full config plus placeholder list for its trigger event
7. **Edit predefined EMAIL**: `PUT /:id` allows `subject`/`body`/`is_active`/`tag` + `channel_config.from_name`/`reply_to`/`cc_recipients`/`bcc_recipients`; rejects `notification_type`/`channel`/`channel_config.from_address`/`channel_config.to_recipients` changes with 400
8. **Edit predefined SMS**: `PUT /:id` allows `body`/`is_active`/`tag` only; any change inside `channel_config` returns 400
9. **Edit predefined → audit**: After edit, `admin_audit_logs` has one row per changed scalar field or per changed top-level key inside `channel_config` with `entity_type = 'notification_template'`, `entity_id`, `previous_value`, `new_value`, `performed_by`, and a UI-friendly `note`
10. **Create custom EMAIL**: `POST` with `channel = EMAIL` and `channel_config.from_address` at an allowed domain (e.g., `anything@theshowproducers.com`) succeeds; FROM at any other domain returns 400
11. **Custom SMS rejected (Email-only scope)**: `POST` with `channel = SMS` returns 400 — custom create is Email-only this sprint (V2 `77.x`). (The SMS `channel_config` validator still covers predefined SMS edits and a future custom-SMS add, but custom create does not accept `channel = SMS`.)
12. **Cross-channel rejection**: on the custom EMAIL path, `POST` with `channel = EMAIL` and an SMS-only key (`sender_id`) in `channel_config` returns 400; on the predefined SMS path, a `PUT` that adds an email-only key (`from_name`) to an SMS row's `channel_config` returns 400 (predefined SMS allows no `channel_config` edits). (Custom `channel = SMS` is already rejected at the channel check — step 11.)
13. **Delete custom**: `DELETE /:id` works for custom, returns 400 for predefined
14. **Backward compat**: All 14 active `sendFromTemplate()` flows still work — new columns are nullable, `channel` enum migration is no-op for existing rows (all `'EMAIL'`), the mailer doesn't read `channel_config` yet so existing behavior is unchanged. Smoke-test: trigger a registration email, password reset, contact us, lead distribution run, and a Stripe test webhook

## Gaps / Open Questions to Confirm

The following items are either undecided, deferred, or worth surfacing before implementation begins. Each is tagged with severity: **Block** = needs an answer before coding; **Soft** = can be decided during implementation; **Defer** = tracked for a future plan.

### UI / UX gaps not in the schema

| # | Gap | Severity | Notes |
|---|---|---|---|
| 1 | **WYSIWYG editor library not specified** | Block | User story #5 requires a WYSIWYG editor. Candidates: TipTap, Quill, Lexical, CKEditor. Editor choice affects DTO validation (sanitized HTML vs Markdown vs raw) and placeholder-picker integration. |
| 2 | **Search fields not finalized** | Soft | Currently proposed: `template_name`, `subject`, `notification_type`. Confirm whether `body` should also be searched (could be slow without GIN index on `body`). |
| 3 | **Default page size / max page size** | Soft | Plan says "paginated" — pick the same defaults as other admin list endpoints. |
| 4 | **Authorization permission slug** | Block | Plan says "reuse existing authorization pattern" but doesn't name the slug. Need to confirm: a new `notification_template.read/write/delete` permission group, or fold into an existing one? |
| 5 | **Template preview / test send** | Defer | Client likely expects "preview with sample data" and "send test to my email" — not in current scope. Worth flagging as a fast-follow. |
| 6 | **Template clone / "Save as new"** | Defer | Common admin shortcut. Not in scope. |
| 7 | **Optimistic locking for concurrent edits** | Soft | Two admins editing the same template at once. Adding an `If-Match` header on `updated_at` would prevent silent overwrites. |
| 8 | **Draft vs published state** | Soft | Currently `is_active` toggles whether a template fires. There's no "draft" state — edits go live the moment they save. Confirm with client whether that's acceptable. |

### Schema details to confirm

| # | Gap | Severity | Notes |
|---|---|---|---|
| 9 | **DELETE — soft or hard?** | Block | For custom templates, is `DELETE /:id` a hard delete or a soft delete (`deleted_at` column)? Most admin entities in this codebase use soft delete — check existing pattern in `admin-backend-api`. |
| 10 | **Multi-language strategy** | Soft | `language` column already exists (default `en`). Plan doesn't specify whether one template = one row per language, or one row with translated variants. Today's seeder writes only `en`; confirm if Spanish/other are expected. |
| 11 | **Predefined SMS templates — should any be seeded?** | Block | The client Excel has 4 SMS templates. Currently the plan seeds 0 SMS rows (the 18 seeded slugs are all EMAIL). Decide: seed the 4 SMS slugs as predefined rows (channel=SMS, body=copy from Excel, channel_config=null until provider ships), or wait until the SMS provider plan. |
| 12 | **`subject` for SMS** | Soft | `subject` stays nullable. UI should hide the subject field when `channel = SMS`; service-layer should reject non-null subject on SMS rows (or just ignore it). Confirm preference. |
| 13 | **Sender ID default for predefined SMS** | Block (only if #11 = yes) | If we seed SMS predefined rows, where does the system-controlled `sender_id` come from at send time? Configuration table? Env var? Per-show setting? |
| 14 | **`NotificationLog` updates for SMS** | Defer | The existing `NotificationLog` model has an `email VarChar(255)` column. SMS sends need a `phone` column. Not needed for this CRUD plan (no sending), but flagged for the SMS provider plan. |
| 15 | **JSONB indexing strategy** | Defer | The plan filters on top-level columns only. If admins want to filter "show me all templates that include `cc=ops@...`", a GIN index on `channel_config` would be needed. Not required today. |
| 16 | **Bulk operations (enable/disable all of type X, bulk delete)** | Defer | Not in scope; flag for follow-up. |
| 17 | **`channel_config = null` vs `channel_config = {}`** | Soft | Predefined EMAIL rows have nullable system-controlled keys. Store as `{ "from_name": "...", "reply_to": "...", "from_address": null, "to_recipients": null, "cc_recipients": [], "bcc_recipients": [] }` or as `{ "from_name": "...", "reply_to": "..." }` (system keys absent)? Pick a convention for consistency. |
| 18 | **Trigger event `label` source** | Soft | `trigger_events.label` is a human-readable name for the dropdown. Who curates these — eng or content team? Confirm content owner. |
| 19 | **Custom trigger events: admin-creatable?** | RESOLVED — No. | `trigger_events` remains strictly code-controlled. `slug` is globally unique (FK target); `is_custom` is a flag marking the predefined set — all seeded rows are `is_custom = false`. No `POST /trigger-events` endpoint. *(2026-06-11: composite-unique + partial-index design replaced by global unique slug — Postgres FKs can't reference partial unique indexes; future custom triggers need distinct slugs.)* |

### Scope already deferred (re-confirming)

The following are explicitly **out of scope** for this plan but listed here so reviewers see them in one place:

- Mailer modifications to read `channel_config` (CC/BCC/variable FROM)
- Worker that reads `schedule_config` to delay sends
- Worker that reads `follow_up_config` to dispatch follow-ups
- SMS provider integration (Twilio / etc.)
- Stop conditions on follow-ups (`stop_if: "lead_claimed"` etc.)
- Inter-template follow-ups (a follow-up step referencing a different template by `template_id`)
- Module-specific trigger events for Contracts, Cart, Orders, Booth, etc.
- The 26 templates in the client Excel that depend on the above triggers
- Dynamic recipient resolution at send time (`{salesperson_email_address}` etc.)
- PUSH channel

---

## Related documents

- `EMAIL_SMS_DB_DESIGN_REVIEW.md` — concise TL-facing design review (column→requirement traceability, JSONB shapes, migration ordering)
- `EMAIL_SMS_STORY_REVISIONS.md` — V1: suggested revisions to the original 6 user stories (historical baseline)
- `EMAIL_SMS_STORY_REVISIONS_V2.md` — **V2 (current)**: story-by-story verdicts across the two-epic backlog (76.x / 77.x) + the V1→V2 change log
- `EMAIL_SMS_KNOWN_ISSUES.md` — running register of deferrals, dependencies, and contradictions (reconciled against V2)
- `EMAIL_SMS_EFFORT_JUSTIFICATION.md` / `EMAIL_SMS_EFFORT_SUMMARY.md` — effort justification (engineering + management audiences)
