# Email & SMS Management — DB Design Review

**For:** Tech Lead review
**Scope:** CRUD-only (admin panel). Mailer/scheduler/SMS-provider work is deferred to follow-on plans.
**Source of truth schema:** `admin-backend-api/prisma/schema.prisma` (other 4 services use `db push` only).

---

## 1. Schema diagram

```
┌──────────────────────────────────────────────────────────┐
│  notification_templates  (existing, extended)            │
├──────────────────────────────────────────────────────────┤
│  id (PK)                                                 │
│  notification_type ──┐  ◄── FK → trigger_events.slug     │
│  channel             │  ◄── enum NotificationChannel     │
│  subject (nullable, NULL for SMS), body, language        │
│  is_active, created_at, updated_at                       │
│  ─── NEW COLUMNS (6) ────────────────────────────────────│
│  template_name                                           │
│  type                ◄── enum NotificationTemplateType   │ // change column name to Tag
│  channel_config (JSONB)  ← shape varies by channel       │
│  is_predefined (boolean)                                 │
│  schedule_config (JSONB)   ← array, channel-agnostic     │
│  follow_up_config (JSONB)  ← array, channel-agnostic     │
└──────────────────┬───────────────────────────────────────┘
                   │ N
                   ▼
        ┌──────────────────┐         ┌───────────────────┐
        │  trigger_events  │         │ admin_audit_logs  │
        │  (NEW, 18 rows)  │         │  (existing, +1    │
        ├──────────────────┤         │   entity_type)    │
        │  id (PK)         │         ├───────────────────┤
        │  slug            │         │  entity_type =    │
        │  label           │         │   'notification_  │
        │  available_      │         │    template'      │
        │   placeholders   │         │  entity_id ──────►│ notification_
        │   (JSONB)        │         │  previous_value   │ templates.id
        │  is_custom       │         │  new_value        │ (logical, no FK)
        │   (boolean,      │         │  performed_by ───►│ users.id
        │   default false) │         │  note, created_at │
        │                  │         └───────────────────┘
        │  UNIQUE          │
        │  (slug,is_custom)│
        │  + partial UQ on │
        │  slug WHERE      │
        │  is_custom=false │
        │  (FK target)     │
        └──────────────────┘

┌────────────────────────────┐
│ allowed_from_domains       │  ← Service-layer lookup only;
│  (NEW, 2 rows)             │    no FK from notification_templates
├────────────────────────────┤
│  id (PK), domain (unique), is_active │
└────────────────────────────┘
```

---

## 2. Column → requirement traceability

### `notification_templates` columns

| Column | New / Existing | Requirement it serves | How it's used |
|---|---|---|---|
| `id` | existing | — | PK; entity ref in audit logs |
| `notification_type` | existing (typed change) | Custom templates pick a trigger; predefined are pinned to one. Cross-service mailer lookup. | Lookup key in `sendFromTemplate(notification_type)`. Promoted to FK → `trigger_events.slug`. |
| `channel` | existing (type promoted) | UI "Format" filter; SMS support | `VarChar(50)` → enum `NotificationChannel { EMAIL, SMS }`. Drives `channel_config` shape selection. |
| `subject` | existing | EMAIL templates only | Nullable; required for EMAIL, must be NULL for SMS. UI hides field for SMS. |
| `body` | existing | WYSIWYG body editing (user story #5) | HTML for EMAIL, plain text for SMS. Mailer reads via Handlebars. |
| `language` | existing | Future multi-language | Defaults to `en`; not actively scoped in this plan. |
| `is_active` | existing | Enable/disable toggle | Filter param `?is_active=`; predefined edit allowed. |
| `created_at`, `updated_at` | existing | Audit / list sort | `updated_at` shown in list view. |
| `template_name` | **NEW** | Listing display column (user story #1) | Human-readable name shown in admin grid; searchable. |
| `type` | **NEW** | Type filter (user story #3); Excel taxonomy (Store/Internal/Vendor/Product/PPL) | Enum `NotificationTemplateType`. Decoupled from trigger so admin can categorize independently. |
| `channel_config` | **NEW** | Recipient config (user story #6); FROM/CC/BCC; SMS sender + recipients | Single JSONB column; shape varies by `channel`. Replaces 6 email-shaped columns so SMS rows don't carry NULL email columns. |
| `is_predefined` | **NEW** | Two-tier system (predefined vs custom) per client feedback | Boolean flag. Drives service-layer edit rules. `true` for the 18 seeded rows; `false` for admin-created. |
| `schedule_config` | **NEW** | Time-delay scheduling (client: essential; deferred consumption) | JSONB **array** of `{ delay_value, delay_unit, timezone }`. Stored now, consumed by future scheduler worker. |
| `follow_up_config` | **NEW** | Follow-up sequences | JSONB **array** of `{ delay_value, delay_unit }`. Stored now, consumed by future follow-up worker. |

### Dropped from earlier drafts (rationale)

| Dropped | Why |
|---|---|
| `trigger_event_id` | `notification_type` itself is the FK to `trigger_events.slug`; no separate column needed. |
| `format` | Reuse existing `channel`; UI labels it "Format". |
| `from_address`, `from_name`, `reply_to`, `to_recipients`, `cc_recipients`, `bcc_recipients` | Folded into `channel_config` JSONB. SMS rows don't need NULL email columns; future channels (PUSH, WhatsApp) add new shape variants without schema migrations. |
| `updated_by` | Captured by `admin_audit_logs.performed_by`; don't duplicate on the row. |

### New tables

| Table | Purpose | Why a table (not enum/code constant) |
|---|---|---|
| `trigger_events` | Catalog of valid trigger event slugs + their available placeholders (JSONB). 18 rows seeded, all `is_custom = false`. **Strictly code-controlled** — no admin CRUD endpoints. | Admin UI needs `GET /trigger-events` for the dropdown; `available_placeholders` is data, not code. FK from `notification_templates.notification_type`. The `is_custom` column + composite unique `(slug, is_custom)` are a structural guard ensuring 1:1 mapping: querying by `notification_type` with `is_custom = false` always returns exactly one row. A partial unique index on `slug WHERE is_custom = false` makes `slug` a valid FK target for the predefined set. |
| `allowed_from_domains` | Whitelist of domains a custom EMAIL template can send FROM. 2 rows seeded (`theshowproducers.com`, `thesmallbusinessexpo.com`). | Client wants admins to vary the local part (`anything@allowed-domain`) but not the domain. Lookup avoids code redeploy to change the list. |

### Audit logging — reuse, don't add

`admin_audit_logs` exists. Adds **one enum value** `notification_template` to `AdminAuditEntityType` and one audit row per changed field on edit (`performed_by` from JWT). No new audit table.

---

## 3. JSONB shapes (data examples)

### `channel_config` — varies by `channel`

**EMAIL (predefined — system-controlled keys null):**
```json
{
  "from_address": null,
  "from_name": "Small Business Expo",
  "reply_to": "support@thesmallbusinessexpo.com",
  "to_recipients": null,
  "cc_recipients": ["ops@thesmallbusinessexpo.com"],
  "bcc_recipients": []
}
```

**EMAIL (custom — admin enters everything):**
```json
{
  "from_address": "events@thesmallbusinessexpo.com",
  "from_name": "SBE Events Team",
  "reply_to": "events@thesmallbusinessexpo.com",
  "to_recipients": ["lead-list@thesmallbusinessexpo.com"], // Resolution Engine is required @amrin
  "cc_recipients": [],
  "bcc_recipients": ["analytics@theshowproducers.com"]
}
```

**SMS (predefined — system-controlled):**
```json
{
  "sender_id": null,
  "to_recipients": null
}
```

**SMS (custom):**
```json
{
  "sender_id": "SBE",
  "to_recipients": ["+15551234567", "+15559876543"]
}
```

### `schedule_config` — array; `null` or `[]` means "send immediately"

```json
[
  { "delay_value": 1,  "delay_unit": "hours", "timezone": "America/New_York" },
  { "delay_value": 24, "delay_unit": "hours", "timezone": "America/New_York" },
  { "delay_value": 7,  "delay_unit": "days",  "timezone": "America/New_York" }
]
```

### `follow_up_config` — array; `null` or `[]` means "no follow-up"

```json
[
  { "delay_value": 1, "delay_unit": "hours" },
  { "delay_value": 24, "delay_unit": "hours" }
]
```

> Both `schedule_config` and `follow_up_config` are admin-fillable today but **not read by any worker** in this plan. Shape may grow (e.g., `template_id`, `stop_if`) when the scheduler plan ships — data migration handles that.

---

## 4. Enums

| Enum | Status | Values | Used by |
|---|---|---|---|
| `NotificationChannel` | **NEW** | `EMAIL`, `SMS` | `notification_templates.channel`. Promoted from `VarChar(50)`. PUSH dropped from existing DTO whitelist (no concrete requirement). |
| `NotificationTemplateType` | **NEW** | `Store`, `Internal`, `Vendor`, `Product`, `PPL`, `System` | `notification_templates.type`. Matches Excel taxonomy + adds `System` for non-Excel templates (e.g., `contact_us_acknowledgment`). |
| `AdminAuditEntityType` | existing, +1 | `... + notification_template` | `admin_audit_logs.entity_type` for template edit history. |

## 5. What's explicitly NOT in this plan

- Mailer modifications to consume `channel_config` (CC/BCC/variable FROM)
- Scheduler worker (`schedule_config` consumer)
- Follow-up worker (`follow_up_config` consumer)
- SMS provider integration (Twilio etc.)
- Stop conditions on follow-ups, inter-template follow-up references
- The 26 client-Excel templates whose trigger modules (Contracts, Cart, Orders, Booth) don't exist yet
- Dynamic recipient resolution at send time (`{salesperson_email_address}` etc.) // need to implement 
- PUSH channel
