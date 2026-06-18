# Email & SMS Scheduling — Implementation Plan (Dynamic Scheduling)

**Companion to:** `EMAIL_SMS_SCHEDULING_STORY.md` (the refined story this plan builds) and `EMAIL_SMS_TEMPLATE_INTEGRATION_GUIDE.md` (the per-field "what do I type" wiring cookbook — see §10).
**Date:** 2026-06-18
**Revision (2026-06-18):** Added the first-class `is_schedulable` template flag (+ a `TriggerEvent.supports_scheduling` catalog gate), an explicit per-template **Backfill** mapping (all 18 seeded rows → `is_schedulable = false`), the admin schedule-attach gate, the executor candidate filter, the FOLLOW_UP-without-DRR capture path for existing triggers, and a **Template Schedulability Framework** section pointing to the new companion dev guide. **SMS dispatch and Dynamic Recipient Resolution (DRR) remain explicitly deferred** (§9).
**Revision 2 (2026-06-18, review fixes):** Added `recipient_source` + `replacements_map` columns to `notification_schedules` (§2.1) so ANCHOR_RELATIVE resolves recipients/tokens **from the anchor row** at materialize time — making Example B genuinely end-to-end shippable without DRR (token-only recipients with no anchor column stay DRR-deferred). Changed the admin DTO slot to `schedules?: ScheduleRuleDto[]` to match the `[]` back-relation (§3 item 1). Reconciled the §2.0.4 six-slug trigger-gate backfill with the guide's new-trigger reminder examples (§9). Standardized the known-issues cross-references (§8).
**Scope decisions (locked with the user, 2026-06-16):** full dynamic model (3 schedule kinds + timezone) · **dedicated tables** for config · coverage limited to **built predefined triggers + anchors that exist today** · **domain-state stop-conditions included**.
**Services touched:** `admin-backend-api` (config + migration owner), `background-worker-service` (executor), and a one-line correctness fix in all four mailer-bearing services.

> All file paths below were located during a read-only recon of the five repos and are cited so each build step has a concrete reuse target.

---

## 1. Architecture at a glance

Three layers, each reusing an existing, proven pattern:

```
  ADMIN-BACKEND-API                 BACKGROUND-WORKER-SERVICE
  ┌───────────────────────┐         ┌──────────────────────────────────┐
  │ notification-template │  SQS    │ schedule-dispatch module          │
  │  module (CRUD)        │ refresh │  Registrar  → heartbeat cron      │
  │  + is_schedulable     │ ──────► │  Task       → re-entrancy + log   │
  │  + schedule DTOs      │         │  Service    → materialize+dispatch│
  │  + audit              │         │              (filters schedulable)│
  └──────────┬────────────┘         └───────────────┬──────────────────┘
             │ writes                                │ reads rules / writes occurrences
             ▼                                       ▼
        Postgres:  notification_schedules ──< notification_schedule_occurrences
                                                     │ dispatch via
                                                     ▼  MailerService.sendFromTemplate()
                                                  NotificationLog (PENDING→SENT/FAILED)
```

- **Config** lives in `admin-backend-api`, edited through the existing template module. On save it publishes an **SQS refresh** so the worker reloads live — the mechanism that satisfies the "dynamic, reflects without redeploy" requirement.
- **Schedulability** is a first-class, queryable property of the template (`is_schedulable`), gated by a code-controlled trigger hint (`TriggerEvent.supports_scheduling`). A schedule can only attach to a schedulable template; the worker only materializes occurrences for schedulable, active templates.
- **Executor** lives in `background-worker-service` — the only service with `@nestjs/schedule`, `cron`, `date-fns-tz`, and the mailer. A single **heartbeat cron** (the due-poller) materializes occurrences from rules + resolved anchors and dispatches those that are due.
- **Stop-conditions** are evaluated each tick; remaining occurrences are cancelled when the bound domain state resolves.

---

## 2. Data model (admin-backend-api owns the migration)

`admin-backend-api` is the **source of truth** for schema and migrations; the other four services mirror via `db push` (per `CLAUDE.md`). Add the migration under `admin-backend-api/prisma/migrations/`, then mirror every model/enum/column change into each service's `prisma/schema.prisma` and run `db push`.

This release adds **three** schema concerns, in dependency order:

1. **§2.0 — Schedulability flags:** a first-class `is_schedulable` flag on `NotificationTemplate` plus a `supports_scheduling` catalog gate on `TriggerEvent`. This is the marker that decides whether a template is *eligible* to carry a schedule at all. **(NEW — primary deliverable.)**
2. **§2.1 / §2.2 — The dedicated `notification_schedules` and `notification_schedule_occurrences` tables** (the authoritative store for send-rules and materialized due-sends).
3. **§2.3 — The integrity rule** that binds them: a schedule may only attach to an `is_schedulable = true` template, and a template may only be `is_schedulable = true` if its trigger `supports_scheduling = true`.

> **One-line summary of the new column:** `is_schedulable Boolean @default(false)` is the new first-class column on `NotificationTemplate` (added next to `schedule_config` / `follow_up_config`, `admin-backend-api/prisma/schema.prisma:238-239`). It is *marked*, never inferred from "does a schedule row exist?".

### 2.0 Schedulability flags (NEW)

#### 2.0.1 `NotificationTemplate.is_schedulable` — the per-template marker

The flag lives on the **template**, not (only) the trigger, because schedulability is a property of *this specific row*: a custom template authored on a schedulable trigger may itself be schedulable, while the seeded predefined template on the same trigger may not — and vice-versa. Inferring schedulability from "does a schedule row exist?" is rejected: the marker must be queryable and settable **before** any schedule is attached (the admin UI gates the "Add schedule" affordance on it), and a template can legitimately be schedulable-but-not-yet-scheduled.

```prisma
model NotificationTemplate {
  // ... existing columns (id … is_predefined … schedule_config … follow_up_config …) ...
  is_schedulable    Boolean                  @default(false)
  // ... is_active, timestamps, relations ...

  schedules NotificationSchedule[]   // back-relation to §2.1 (new)
}
```

- **`Boolean @default(false)`, NOT NULL** — honors the prefs (NOT NULL + default, no nullable column). Every existing row receives `false` on column-add; schedulable seeded rows would be promoted by an explicit backfill (§2.0.4 — which promotes zero rows today).
- Placed adjacent to `is_predefined` (line 237) and the dormant `schedule_config`/`follow_up_config` (lines 238–239) so the schedulability cluster reads together.

#### 2.0.2 `TriggerEvent.supports_scheduling` — the catalog gate (RECOMMENDED, ship it)

A matching hint **does** belong on `TriggerEvent`, and we ship it:

- The trigger catalog is code-controlled with no admin CRUD. It already carries the per-trigger metadata (`available_placeholders`) that the admin UI reads to gate what the editor exposes. Whether a trigger is *the kind of event a schedule can hang off* is exactly the same class of code-owned catalog fact, and it is **trigger-wide**: e.g. `forgot_password` must never be schedulable on *any* template, predefined or custom, because the body carries a time-boxed reset link. A per-template flag alone cannot express "no template on this trigger may ever schedule" without trusting every future author to set `is_schedulable = false` by hand.
- It lets the UI and the service **gate** `is_schedulable` at the source: a template may be set `is_schedulable = true` **only if** its trigger's `supports_scheduling = true` (enforced in §2.3 and in the service guard). This turns "which triggers may expose scheduling" into one seeded, reviewable list rather than a convention.
- It is one boolean on a ~21-row, code-controlled table — negligible churn, idempotently upserted by the existing trigger seeder.

```prisma
model TriggerEvent {
  // ... existing columns ...
  supports_scheduling Boolean @default(false)
  // ...
}
```

**Net rule:** `supports_scheduling` (trigger) is the *ceiling* — it says scheduling is conceptually meaningful for this event. `is_schedulable` (template) is the *switch* — it says this particular template is wired and turned on. A template can be `is_schedulable = true` only when its trigger is `supports_scheduling = true`.

#### 2.0.3 Schedulability METADATA — keep it in `schedule_config` JSON, do NOT add columns

Decision: **do not** add `default_schedule_kind` / `default_anchor_entity` / `default_anchor_field` as columns on `NotificationTemplate`. The per-rule authoritative values already live as **first-class columns on `notification_schedules`** (`schedule_kind`, `anchor_entity`, `anchor_field` — §2.1). Reasoning:

- **No query/validation need at the template level.** The dispatcher polls `notification_schedules` / `notification_schedule_occurrences`, never the template's metadata, to decide what fires. Nothing reads a template-level `default_anchor_field` at runtime; duplicating it as a column would be a denormalized copy that can silently drift from the real schedule row.
- **Schema churn vs. benefit.** Three nullable columns mirrored into five `schema.prisma` files, for values that are purely *documentation defaults for a future author*, is churn without a consumer. The only consumer is a human reading the template before they create a schedule.
- **The right home is the existing `schedule_config` JSON** (line 238), which is already STORED and SELECTED (detail select) but read by nothing — it is the designed back-compat / inline slot. We repurpose it as a **non-authoritative author hint**: when a dev marks a template `is_schedulable = true` but hasn't created the `notification_schedules` row yet, they record the *intended* shape here so the next person knows what to wire. Shape:

  ```jsonc
  // NotificationTemplate.schedule_config (author hint only — NOT consumed by the dispatcher)
  {
    "default_schedule_kind": "ANCHOR_RELATIVE",      // ANCHOR_RELATIVE | RECURRING | FOLLOW_UP
    "default_anchor_entity": "CART",                  // CART | PAYMENT_TRANSACTION | ORDER | SHOW | null
    "default_anchor_field":  "expiration_date",       // matching field name on the anchor model, or null
    "notes": "Cart expiry reminder; author the notification_schedules row with offsets -3d/-1d."
  }
  ```

  The authoritative runtime values are always the `notification_schedules` columns. `schedule_config` is advisory; the dev guide documents that you copy these hints into the real schedule row on creation. (`follow_up_config`, line 239, stays as-is for the same advisory role on FOLLOW_UP-kind hints.)

This keeps the **flag** first-class (a real, NOT-NULL boolean) while keeping the **soft metadata** in the JSON slot that was built for exactly this and currently carries nothing.

#### 2.0.4 Backfill (NOT NULL + explicit promotion of the schedulable seeded rows)

Per the prefs: add the columns NOT NULL with `DEFAULT false` (so the column-add is safe on every existing row), then run an **explicit backfill UPDATE** to promote the rows that should be schedulable. Per the verified seeder inventory, **none of the 18 seeded predefined templates rides a wired schedule end-to-end today** — every seeded body is a transactional/event reaction, and the one true conceptual candidate (`lead_daily_summary`, RECURRING) has no built poller/anchor. **Therefore the backfill promotes zero template rows: all 18 stay `is_schedulable = false`.** The flag still ships as first-class and explicit (the seeder sets it on every row going forward — see §2.0.5), so schedulability is *marked*, not inferred.

The trigger-side gate, however, **is** backfilled: we open `supports_scheduling = true` on the small set of triggers where scheduling is conceptually valid against an anchor/cadence that exists or is plausibly buildable, so a future author can mark a (custom or newly-authored) template schedulable without a schema change. Everything else stays gated `false`.

**Per-template `is_schedulable` mapping (all 18 → false), for the record:**

| notification_type | is_schedulable | rationale (from seeder inventory) |
|---|---|---|
| `welcome_email` | false | transactional, carries temp password |
| `forgot_password` | false | security, time-boxed reset link |
| `welcome_email_exhibitor` | false | immediate onboarding |
| `exhibitor_forgot_password` | false | security reset link |
| `contact_us_acknowledgment` | false | instant auto-reply |
| `contact_us_admin_notification` | false | instant internal alert |
| `ppl_order_confirmation` | false | payment receipt, event-driven |
| `ppl_subscription_canceled` | false | immediate cancel confirmation |
| `ppl_subscription_renewal` | false | fired by renewal webhook |
| `company_user_invitation` | false | instant invite (reminder series not wired) |
| `invitation_accepted_to_exhibitor` | false | instant confirmation |
| `lead_assigned_preview` | false | speed is the point |
| `lead_daily_summary` | false | RECURRING candidate, no built poller/anchor |
| `lead_credits_renewed` | false | dormant, no sender/anchor |
| `low_balance_warning` | false | threshold/state-driven, not time-driven |
| `ppl_product_order_payment` | false | per-charge receipt (dunning reminder is a separate, unseeded template) |
| `exhibitor_welcome_admin_created` | false | immediate onboarding, temp password |
| `cart_updated_notification` | false | instant edit notice (expiry reminder is a separate, unseeded template) |

**Migration SQL (admin-backend-api), hand-written per house convention (`ADD COLUMN IF NOT EXISTS`, `COMMENT ON COLUMN`, backfill then constraints already satisfied by DEFAULT):**

```sql
-- 1. Template marker -------------------------------------------------------
ALTER TABLE "notification_templates"
  ADD COLUMN IF NOT EXISTS "is_schedulable" BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN "notification_templates"."is_schedulable" IS
  'First-class marker: this template is eligible to carry a notification_schedules row. '
  'May be true only when the trigger_event.supports_scheduling = true. '
  'Decoupled from is_predefined and from whether a schedule currently exists.';

-- 2. Trigger catalog gate --------------------------------------------------
ALTER TABLE "trigger_events"
  ADD COLUMN IF NOT EXISTS "supports_scheduling" BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN "trigger_events"."supports_scheduling" IS
  'Catalog gate: scheduling is conceptually valid for this code-controlled trigger. '
  'A template may set is_schedulable = true only if its trigger has this = true.';

-- 3. Backfill — templates: explicit, promotes ZERO rows (all 18 stay false).
--    Listed as an explicit no-op UPDATE so the migration documents the decision
--    and any future row that SHOULD be promoted is added here by name.
UPDATE "notification_templates"
   SET "is_schedulable" = false
 WHERE "is_predefined" = true;   -- all 18 seeded predefined rows: not schedulable today

-- 3b. Backfill — triggers: open the catalog gate where scheduling is meaningful.
--     Anchors that exist today: Cart.expiration_date, PaymentTransaction.due_date,
--     Order.paid_in_full_at, Shows.date (weak/date-only). Plus the dormant
--     RECURRING/FOLLOW_UP candidates a future author may legitimately wire.
UPDATE "trigger_events"
   SET "supports_scheduling" = true
 WHERE "slug" IN (
   'cart_updated_notification',   -- Cart.expiration_date → ANCHOR_RELATIVE expiry reminders
   'ppl_product_order_payment',   -- PaymentTransaction.due_date → ANCHOR_RELATIVE dunning
   'lead_daily_summary',          -- RECURRING daily digest cadence
   'lead_credits_renewed',        -- RECURRING per-billing-cycle (dormant until sender wired)
   'company_user_invitation',     -- FOLLOW_UP invite-reminder series
   'ppl_subscription_canceled'    -- FOLLOW_UP win-back series
 );
-- All other triggers remain supports_scheduling = false (e.g. forgot_password,
-- welcome_email, *_reset — must never be schedulable on any template).
```

> **Important — what these six gates do and do NOT enable (reconciles with the integration guide):** opening `supports_scheduling = true` on `cart_updated_notification` / `ppl_product_order_payment` / etc. does **not** make the seeded receipt/notice on those slugs schedulable — those seeded templates stay `is_schedulable = false` permanently (they are transactional, §2.0.4 table). The gate exists for **future *same-trigger* custom templates**: a dev could author a *new custom* template on the existing `cart_updated_notification` trigger and mark it schedulable. **The reminder examples in the integration guide deliberately do NOT reuse these slugs** — Example B authors a *brand-new* trigger `cart_expiration_reminder` (and a separate dunning trigger) with its own `supports_scheduling = true` seeded via the guide flow, because a "cart expiring soon" reminder is a semantically distinct event from a "cart was updated" notice. So there are two independent ways to land a schedulable template: (1) author a custom template on one of these six already-gated triggers, or (2) seed a new trigger with `supports_scheduling = true` (the guide's path). The §9 open-decision list and the guide's Example B both reflect (2) as the primary reminder pattern; these six backfilled gates serve (1).

> **Open product decision:** opening `supports_scheduling` on a trigger is a product statement about which events may *ever* be scheduled. The six slugs above are this plan's recommendation; confirm with the user before seeding (tracked in §9).

#### 2.0.5 Seeder change (mark the flag first-class, don't infer it)

`notification-template.seeder.ts` currently merges `{ ...template, ...meta, is_predefined: true }` (line 703) and never sets `is_schedulable`. Add `is_schedulable` **explicitly** to that data block so every seeded row gets a deterministic, reviewed value (all `false` today) rather than relying on the DB default. Per-template values come from `TEMPLATE_META` (extend the `Record` value type to `{ template_name, tag, is_schedulable }`) so the value sits beside the other catalog facts:

```ts
const data = { ...template, ...meta, is_predefined: true, is_schedulable: meta.is_schedulable };
```

`trigger-event.seeder.ts` (idempotent upsert, lines 222–247) gets `supports_scheduling` added to **both** the `update` and `create` blocks, sourced from the per-trigger seed list, so re-runs converge the gate to the §2.0.4 set. Because the template seeder is create-only (never clobbers admin edits) the flag is only authoritative for the *initial* create; admin edits thereafter flow through the service (see §3).

#### 2.0.6 Mirror to the four sibling services + db push

`is_schedulable` (on `NotificationTemplate`), `supports_scheduling` (on `TriggerEvent`), and the §2.1/§2.2 models/enums must be copied **identically** into:

- `exhibitor-backend-api/prisma/schema.prisma`
- `background-worker-service/prisma/schema.prisma`
- `external-api-service/prisma/schema.prisma`
- `pulse-broker-service/prisma/schema.prisma`

Then `prisma db push` in each (these four never own migrations). The worker reads `is_schedulable` (and the schedule rows) to decide eligibility; the others carry the column for schema parity. **Avoid raw-SQL-only constructs (partial/conditional indexes) on the new tables** — the team deliberately avoids them because a sibling `db push` drops anything not expressible in `schema.prisma` (same reason the predefined-uniqueness invariant is enforced in code, not a partial index).

### 2.1 `notification_schedules` — one row per send-rule
| Column | Type | Notes |
|---|---|---|
| `id` | Int PK (`autoincrement`) | Int PK per schema prefs |
| `notification_template_id` | Int FK → `notification_templates.id` | `onDelete: Cascade`; **target row must have `is_schedulable = true`** (§2.3) |
| `schedule_kind` | enum `NotificationScheduleKind` `{ ANCHOR_RELATIVE, RECURRING, FOLLOW_UP }` | authoritative kind (the template's `schedule_config.default_schedule_kind` is only an advisory hint) |
| `anchor_entity` | enum/string, nullable | e.g. `CART`, `PAYMENT_TRANSACTION`, `ORDER`, `SHOW` (ANCHOR_RELATIVE only) |
| `anchor_field` | String, nullable | e.g. `expiration_date`, `due_date`, `paid_in_full_at`, `date` |
| `recipient_source` | String, nullable | ANCHOR_RELATIVE only: the recipient email field **on the anchor record** the materializer reads to populate `to[]` (e.g. `client_email` for `CART`, `billing_email` for `ORDER`). Nullable anchors must be guarded; if the source field is null the occurrence is `SKIPPED`. **If recipients are tokens (`{salesperson}`) rather than a column on the anchor, this is DRR (#3) → deferred.** See §4.7. |
| `replacements_map` | Json, nullable | ANCHOR_RELATIVE only: maps each body/subject `{{token}}` to a literal field expression on the anchor record, e.g. `{ "name": "client_first_name + ' ' + client_last_name", "cart_number": "cart_number", "expiration_date": "expiration_date" }`. The materializer resolves these from the anchor row to build `replacements` for `sendFromTemplate`. (FOLLOW_UP uses `recipients_snapshot` instead — §2.2.) |
| `offsets` | Json | array of `{ value:int≥0, unit:'days'|'hours', direction:'before'|'after' }`; multi-offset = multiple entries |
| `recurrence` | Json, nullable | RECURRING only: `{ daysOfWeek:[...], time:'HH:MM' }` or `{ intervalDays:int }` |
| `send_time` | String `HH:MM`, nullable | ANCHOR_RELATIVE/FOLLOW_UP time-of-day |
| `timezone` | String | `'EVENT'` or an IANA zone (e.g. `America/New_York`) |
| `follow_up` | Json, nullable | FOLLOW_UP only: `{ delayDays:int≥0, frequency, repeatCount }` |
| `stop_condition` | enum `NotificationStopCondition`, nullable | code-controlled set: `CONTRACT_SIGNED`, `QUESTION_ANSWERED`, `CART_CONVERTED`, … `NONE` |
| `end_window_at` | Timestamptz, nullable | optional hard stop for RECURRING |
| `is_enabled` | Boolean `@default(true)` | |
| `created_at` / `updated_at` | Timestamptz | mirror existing column conventions |

### 2.2 `notification_schedule_occurrences` — materialized due-sends
| Column | Type | Notes |
|---|---|---|
| `id` | BigInt PK | high-volume table; mirror `NotificationLog.id` (BigInt — the one allowed BigInt exception) |
| `schedule_id` | Int FK → `notification_schedules.id` | `onDelete: Cascade` |
| `anchor_instance_ref` | String, nullable | identifies the specific anchor record (e.g. `cart:123`) for ANCHOR_RELATIVE |
| `recipients_snapshot` | Json, nullable | The recipients + replacements to dispatch with. **FOLLOW_UP:** resolved at the live send site and snapshotted (§4 item 8). **ANCHOR_RELATIVE:** resolved at materialize time from the anchor row via `recipient_source` + `replacements_map` (§4 item 3 / §2.1). Replayed verbatim at dispatch in both cases. |
| `fire_at` | Timestamptz | resolved absolute send instant (UTC) |
| `status` | enum `{ PENDING, SENT, SKIPPED, CANCELLED, FAILED }` `@default(PENDING)` | |
| `dedupe_key` | String `@unique` | `schedule_id + anchor_instance_ref + fire_at` → idempotency |
| `notification_log_id` | BigInt FK → `notification_logs.id`, nullable | links the actual send |
| `created_at` / `updated_at` | Timestamptz | |

Indexes: `(status, fire_at)` for the due-poller; `(schedule_id)`.

### 2.3 Integrity rule — schedules attach only to schedulable templates (NEW)

This is the seam that ties §2.0 to §2.1:

1. **Trigger → template ceiling:** a `NotificationTemplate` may be set `is_schedulable = true` **only if** its `trigger_event.supports_scheduling = true`. Enforced in the admin service guard (placed beside `assertPlaceholdersAllowed`, `notification-template.service.ts:572-592`) — a single `findUnique` on the trigger before staging the flag.
2. **Template → schedule gate:** a `notification_schedules` row may reference a `notification_template_id` **only if** that template's `is_schedulable = true`. Enforced in the schedule-create/update service path (the same merge layer that handles `collectScalarUpdates`).
3. **Predefined two-tier matrix:** `is_schedulable` is editable on predefined rows (it is *not* a routing/recipient field) — this is precisely the documented mechanism for turning on scheduling for a seeded template once an anchor + sender exist. See §3 item 8 for the full who-may-set decision.

Both rules are **enforced in the service layer**, not as DB CHECK constraints or partial indexes (consistent with the team's avoid-raw-SQL-constructs stance so sibling `db push` stays clean).

### Why dedicated tables (not the JSON columns)

Multi-offset, recurrence, dedupe, "never rewrite a sent occurrence", and the audit requirement are all cleaner with first-class rows. The existing `schedule_config` / `follow_up_config` JSONB columns on `NotificationTemplate` (`admin-backend-api/prisma/schema.prisma:238-239`) are **repurposed as advisory author hints** (§2.0.3) — kept, but never read by the dispatcher; the new tables are the authoritative store.

---

## 3. Layer A — Admin config (admin-backend-api)

Extend the existing module — do not create a new one.

**Files (existing, to extend):**
- `src/admin/notification-template/notification-template.controller.ts` (`:1-306`)
- `src/admin/notification-template/notification-template.service.ts` (`:26-76` select consts, `:253-281` create, `:285-378` update + audit, `:399-423` predefined matrix, `:462-492` collectScalarUpdates, `:572-592` placeholder guard, `:611-633` snapshot)
- `src/admin/notification-template/dto/notification-template.dto.ts` (`:56-97`, `:175-422` nested DTO patterns)

**Work:**
1. **DTOs** — add `ScheduleRuleDto` (and nested `OffsetDto`, `RecurrenceDto`, `FollowUpDto`) using the **existing** validation patterns: `@IsOptionalNonNull`, `@ValidateNested` + `@Type`, and the `ConfigEmailField` / `ConfigStringField` decorator-factory style. Reuse the `extractSimplePlaceholders` / `assertPlaceholdersAllowed` flow if any schedule field references placeholders.
   - **Cardinality (resolves the `schedule?` vs `schedules[]` mismatch):** the create/update DTO slot is `schedules?: ScheduleRuleDto[]` (an **array**), matching the `schedules NotificationSchedule[]` back-relation (§2.1) — a single template can carry multiple distinct rules (e.g. one `ANCHOR_RELATIVE` plus one `FOLLOW_UP`). Multi-offset within one rule is still the rule's `offsets` array; multiple *rules* are separate array entries. The worked examples in `EMAIL_SMS_TEMPLATE_INTEGRATION_GUIDE.md` show a single-element array for clarity (the `"schedule": {…}` payloads there are illustrative of one rule — wrap in `"schedules": [ {…} ]` for the real DTO). The attach-gate (item 7) checks the array is empty unless `is_schedulable=true`.
2. **Service** — read/merge schedules following the existing `collectScalarUpdates` / `collectChannelConfigUpdate` merge semantics (provided keys overwrite, unprovided preserve). Validate anchor/offset/recurrence/timezone shape per kind; enforce the **two-tier matrix** via the existing `assertPredefinedFieldsEditable` (predefined recipients stay read-only).
3. **Audit** — extend `NotificationTemplateAuditSnapshot` / `toAuditSnapshot` to include schedule fields **and `is_schedulable`** (see item 9); emit per-change rows via `AdminAuditService.record/recordMany` + `buildNotificationTemplateUpdateNote` (`src/admin/common/audit/`).
4. **Live refresh** — on schedule create/update/delete, **publish an SQS message** that the worker consumes to reload schedules without restart. Reuse the worker's `ModuleRegistry` allow-list + `SchedulerControlService.refreshInterval()` path (see Layer B). Add a `schedule-dispatch` refresh method to the allow-list.
5. **Detail/Listing** — include the template's schedules in the detail response (`NOTIFICATION_TEMPLATE_DETAIL_SELECT`); keep the list select lean. **Add `is_schedulable` to BOTH the list and detail selects** (`service.ts:26-36` and `:43-68`) — it auto-propagates into the Prisma `GetPayload`-derived response types.
6. **`is_schedulable` create/update field** — add `is_schedulable?: boolean` to `CreateNotificationTemplateDto` (validate as `is_active` does: plain `@IsBoolean`, optional) and to `UpdateNotificationTemplateDto` (`@IsOptionalNonNull @IsBoolean`). Write it in the create data block (`notification-template.service.ts:253-281`, default `false`) and add it to the `collectScalarUpdates` tuple (`:470-479`) exactly like `is_active` so it gets per-key audited merge for free.
7. **Trigger-ceiling + attach-gate (new service guard)** — beside `assertPlaceholdersAllowed` (`:572-592`), called from both `createTemplate` and `updateTemplate`:
   - **Ceiling:** if the effective `is_schedulable` would be `true`, `findUnique` the trigger and reject unless `trigger_event.supports_scheduling = true` (§2.3 rule 1).
   - **Attach-gate:** one or more `ScheduleRuleDto` may be present **only if** the effective `is_schedulable` is `true` (§2.3 rule 2):
     ```ts
     private assertSchedulableForScheduleRule(
       effectiveIsSchedulable: boolean,
       dto: { schedules?: ScheduleRuleDto[] },
     ): void {
       if ((dto.schedules?.length ?? 0) > 0 && !effectiveIsSchedulable) {
         throw new BadRequestException(
           'A schedule rule can only be attached to a template with is_schedulable=true',
         );
       }
     }
     ```
     `effectiveIsSchedulable = dto.is_schedulable ?? existing.is_schedulable` on update; `dto.is_schedulable ?? false` on create. Also **reject turning `is_schedulable` off** while enabled schedule rows exist for the template (count `notification_schedules WHERE notification_template_id = id AND is_enabled = true`), to avoid orphaned live rules.
8. **Two-tier matrix — who may set/edit `is_schedulable` on predefined rows:**
   - **Custom templates:** freely settable (the admin owns the row), subject to the trigger ceiling.
   - **Predefined templates:** **allow** editing `is_schedulable` (and attaching a schedule) — this is precisely the documented mechanism for an admin/dev to turn on scheduling for a seeded template once an anchor + sender exist. It is NOT a routing/recipient field, so it does not violate the "predefined FROM/TO is system-controlled" rule that `assertPredefinedFieldsEditable` (`service.ts:399-423`) enforces. **Do NOT add `is_schedulable` to the predefined read-only set.** Keep `notification_type`, `subject`-on-SMS, and the non-`PREDEFINED_EDITABLE_CONFIG_KEYS` channel_config keys locked exactly as today. Rationale: locking `is_schedulable` on predefined rows would make every seeded template permanently unschedulable and defeat the future-dev wiring path. SMS stays seeder/predefined-only, so `is_schedulable` on an SMS row is reachable only through this predefined matrix, never the EMAIL-only create flow.
9. **Audit** — add `is_schedulable` to `NotificationTemplateAuditSnapshot` (`audit-note.builder.ts:393-401`) and to `toAuditSnapshot` (`service.ts:611-633`) so create/delete notes surface it; the per-field `buildNotificationTemplateUpdateNote` already covers the scalar update path with no builder change.

---

## 4. Layer B — Executor (background-worker-service)

New module `src/scheduler/schedule-dispatch/` following the **Task → Registrar → Service** triple used by `low-balance` and `payment-charge`.

**Reuse targets (existing):**
- Registrar/cron pattern: `src/scheduler/low-balance/low-balance-scheduler.registrar.ts` (`:34-60`)
- Task re-entrancy + lifecycle log: `src/scheduler/low-balance/low-balance.task.ts` (`:1-55`)
- Due-poller shape: `src/jobs/payment-charge/payment-charge.service.ts` (`:60-87` — `status='scheduled' AND due_date<=now()`; `:167` atomic `claimRow` via `updateMany` status-guard) and `cart-maintenance` (`expiration_date<=now()`)
- Settings knob: `src/common/ppl-settings/ppl-settings.service.ts` (`getInt`, TTL cache + `invalidate`)
- Hot-reload: `src/scheduler/scheduler-control.service.ts` (`:29-91`) + `src/queue/module.registry.ts` (`:26-66`)
- Send + log: `src/notification/mailer.service.ts` (`sendFromTemplate`, `:87-181`)
- Existing live send sites (for FOLLOW_UP capture): `src/notification/lead-notification.service.ts:86`, `src/notification/low-balance.service.ts:111`, `src/notification/daily-summary.service.ts:125`
- Module registration: `src/scheduler/scheduler.module.ts` (`:1-42`)

**Work:**
1. **Registrar** — register one **heartbeat cron** whose interval comes from a new `ppl_settings` key (e.g. `schedule_dispatch_interval_minutes`, default 5, clamped). Re-register on SQS refresh (mirrors the existing registrars; add to `SchedulerControlService.refreshInterval()` in its own try/catch).
2. **Task** — wrap `ScheduleDispatchService.runTick()` with the existing `isRunning` re-entrancy guard + `ApplicationLogService` started/completed/failed lifecycle; swallow errors so a tick never throws upward.
3. **Service `runTick()`** — two phases:
   - **Materialize:** load enabled `notification_schedules`; for `ANCHOR_RELATIVE`, query the anchor records near the offset window (same "rows past/near a timestamp" model as payment-charge/cart-maintenance); compute each `fire_at` with **`date-fns-tz`** in the rule's timezone (`EVENT` → resolve the anchor record's timezone where modelled — only `Shows.timezone` exists today; else the IANA zone), DST-correct; **upsert** PENDING occurrences keyed by `dedupe_key`. For `RECURRING`, compute the next due instant(s) from the recurrence spec. For `FOLLOW_UP`, compute from the trigger timestamp captured when the trigger fired (item 8).
   - **Dispatch:** select occurrences with `status=PENDING AND fire_at<=now() ORDER BY fire_at`; claim each atomically (`updateMany WHERE {id, status:PENDING} SET status=SENDING`, mirroring `payment-charge` `claimRow`); for each, dispatch via `MailerService.sendFromTemplate()`, link the resulting `NotificationLog`, mark `SENT`/`FAILED`. SMS-channel occurrences are **SKIPPED with reason "SMS provider not integrated"** until #2 lands.
4. **Stop-conditions** — before dispatch (and once per tick), evaluate each rule's `stop_condition` against domain state (contract signed? question answered? cart converted?); set remaining occurrences for that schedule/anchor-instance to `CANCELLED`. Stop-conditions are an enumerated resolver set — no admin-authored logic.
5. **Dev manual trigger** — optionally add a `POST /manual-trigger/schedule-dispatch/run` route in the existing dev/staging-only `ManualTriggerModule` for testing.
6. **Candidate filter (materialize phase):** the rule-loading query joins to the template and **filters `notification_templates.is_schedulable = true AND is_active = true`**. A disabled flag or inactive template ⇒ no occurrences materialized. This is the executor-side honoring of the same first-class gate the admin enforces.
7. **ANCHOR_RELATIVE — confirmed anchor table** (verified against `admin-backend-api/prisma/schema.prisma`):

   | `anchor_entity` | Model (schema line) | `anchor_field` | `recipient_source` (no-DRR email column) | Type / nullability | Poller predicate to clone | Notes |
   |---|---|---|---|---|---|---|
   | `PAYMENT_TRANSACTION` | `PaymentTransaction` (1919) | `due_date` | via `order.billing_email` (join) | `Timestamptz` NOT NULL, `@@index([status, due_date])` | `payment-charge.chargeScheduled()` (`status=scheduled AND due_date<=now()`) | Strongest anchor; proven cron-poll shape. |
   | `CART` | `Cart` (2548) | `expiration_date` | `client_email` (nullable, `:2562`) | `Timestamptz?`, indexed `@@index([expiration_date])` | `cart-maintenance` (`expiration_date <= now()`) | Nullable date AND nullable recipient — guard both; null ⇒ SKIPPED. |
   | `ORDER` | `Order` (1460) | `paid_in_full_at` | `billing_email` (nullable) | `Timestamptz?`, set on completion | n/a (set after event) | FOLLOW_UP-style only — fires after, not a forward window. |
   | `SHOW` | `Shows` (2200) — model is **`Shows`**, not `Show` | `date` | no column recipient ⇒ **DRR (#3)** | `@db.Date` (date-only), **nullable**, `date_to_be_added` TBA flag, `timezone VarChar(50)?` | n/a | WEAK: date-only, no time, no end/move-in/out column, AND show-relative recipients are tokens (needs DRR). Deferred — §9. |

   `fire_at` is computed with `date-fns-tz` in the rule timezone (`EVENT` ⇒ resolve the anchor record's `timezone` where it exists; else the rule's IANA zone), DST-correct, then upserted as a PENDING occurrence keyed by `dedupe_key`.

   **Recipients + replacements for ANCHOR_RELATIVE (no DRR, when the anchor row carries them).** ANCHOR_RELATIVE has **no existing send site** to snapshot from (unlike FOLLOW_UP, item 8), so the materializer must resolve both the recipient list and the `{{token}}` replacements **from the anchor record itself** using two new columns on `notification_schedules` (§2.1): `recipient_source` (the email field on the anchor model — e.g. `Cart.client_email`, `Order.billing_email`) and `replacements_map` (token → anchor-field expression). At materialize time the poller reads the anchor row, evaluates `recipient_source` → `to[]` and `replacements_map` → `replacements`, and stores them on the occurrence (`recipients_snapshot`) so dispatch replays them exactly like FOLLOW_UP. **This is in scope only when the recipient is a real column on the anchor row** (Cart/Order/PaymentTransaction all carry an email field). If a template's recipients are tokens with no column on the anchor (`{salesperson}`, `{all speaker emails}`), that resolution **is DRR (#3) and stays deferred** — such a schedule is author-able but its occurrences `SKIP` with reason `"recipient requires DRR (#3)"`. Nullable recipient sources (`Cart.client_email` is nullable, `schema.prisma:2562`) are guarded: a null source ⇒ occurrence `SKIPPED`. This keeps the §6/Q4 DRR boundary honest: per-anchor *column* recipients ship now; per-anchor *token* recipients defer.
8. **FOLLOW_UP capture WITHOUT DRR (the key to staying in scope):** existing seeded triggers already fire at concrete call sites that **already hold both the domain anchor id and the resolved recipient list** and already call `MailerService.sendFromTemplate(...)`. Confirmed sites: `lead-notification.service.ts:86` (`lead_assigned_preview`), `low-balance.service.ts:111` (`low_balance_warning`), `daily-summary.service.ts:125` (`lead_daily_summary`). To schedule a follow-up after one of these, at the existing send site (after the instant send succeeds) **INSERT one occurrence row that snapshots the recipients + replacements the site already resolved** (into `recipients_snapshot`, §2.2) with `fire_at = now() + follow_up.delayDays`. The dispatch poller then **replays that captured snapshot** — it never re-resolves recipients dynamically, which is exactly the DRR work being deferred (#3). For a FOLLOW_UP series (multiple delays / `repeatCount`), the poller re-enqueues the next occurrence on each successful send until the count is met or the `stop_condition` cancels the remainder. DRR is only needed for NOT-yet-seeded triggers that have no existing send site supplying recipients; those stay deferred.
9. **Occurrence → `NotificationLog` linking & dedupe:** the `dedupe_key` unique (`schedule_id + anchor_instance_ref + fire_at`) means re-running a tick or re-materializing never produces a duplicate send, and already-SENT occurrences are never rewritten. After dispatch, write the returned `NotificationLog.id` into `occurrence.notification_log_id`.
10. **SMS stays SKIPPED:** any occurrence whose template `channel=SMS` is marked `SKIPPED` with reason `"SMS provider not integrated"` — no send attempted (consistent with the deferred SMS-provider scope; there are 0 SMS templates today regardless).

### 4.y Which seeded templates get scheduling NOW vs deferred

**End-to-end schedulable NOW (flag flipped + wired with existing anchors / known recipients):**
- **None of the 18 seeded templates ship `is_schedulable=true`.** Every seeded body is a transactional/event reaction; none today rides a wired forward anchor or recurring poller. So Phase-3/4 deliver the **framework + worked examples**, and `is_schedulable=true` is reserved for templates a dev explicitly wires (see `EMAIL_SMS_TEMPLATE_INTEGRATION_GUIDE.md`).

**Best in-seed candidates (documented as the worked examples, still ship FALSE until their poller/template exists):**
- `lead_daily_summary` — canonical **RECURRING** example. Has a known recipient at its existing send site (`daily-summary.service.ts:125`) so it is recurring-capturable without DRR, but the daily digest poller is not built ⇒ ships FALSE.
- `company_user_invitation`, `ppl_subscription_canceled` — natural **FOLLOW_UP** reminder/win-back candidates; recipients known at send time (no DRR), but no reminder template/sender wired ⇒ FALSE.

**Anchors that exist but whose REMINDER template is NOT seeded (author per the integration guide):**
- `PaymentTransaction.due_date` (ANCHOR_RELATIVE dunning reminder) and `Cart.expiration_date` (cart-expiring-soon reminder) are real anchors today, but the reminder templates are not among the 18 — the receipts/notices that exist (`ppl_product_order_payment`, `cart_updated_notification`) stay FALSE.

**Deferred and why:**
- `lead_credits_renewed` — fully seeded but **dormant** (no sender/anchor); FALSE until the renewal event is wired.
- The 3 bodiless stubs (`lead_claimed_full_details`, `lead_claimed_by_other`, `lead_distribution_expired`) — trigger-only, **no template row exists**; not applicable until authored.
- Anything needing **DRR** (recipients are tokens like `{salesperson}`) or **SMS dispatch** — explicitly deferred (#3, #2).
- Show-relative schedules — `Shows` anchor is date-only/nullable with no end/move-in column; needs new datetime columns first.

---

## 5. Layer C — Bundled correctness fix (Known-Issue #21)

Independently agreed to ship "together with the scheduling logic." The live send path selects a template without an `is_predefined` filter or `orderBy`, so an active **custom** template on a dispatched trigger can nondeterministically shadow the predefined one.

**Fix:** add `is_predefined: true` (+ a deterministic `orderBy`) to the template lookup in every `sendFromTemplate`:
- `background-worker-service/src/notification/mailer.service.ts` (`:92-107`)
- `admin-backend-api/src/common/services/mailer.service.ts`
- `external-api-service/src/common/services/mailer.service.ts`
- `exhibitor-backend-api/src/common/services/mailer.service.ts`

**Interaction with `is_schedulable`:**
- **Scheduled sends are inherently immune to #21** — an occurrence dispatches a **specific template id** (via the schedule's `notification_template_id`), so there is no slug-ambiguity for scheduled paths.
- **The flag does not replace the #21 fix** — `is_schedulable` does not filter the live event-triggered `sendFromTemplate` path; that path still selects by slug and is fixed by the `is_predefined`/`orderBy` change. Both ship together so the live (non-scheduled) triggers also send the predefined row deterministically.

---

## 6. Reuse map

| Need | Existing asset to reuse |
|---|---|
| Cron + timezone math | `@nestjs/schedule` + `cron` v4 + `date-fns-tz`; `low-balance-scheduler.registrar.ts` |
| Hot-reload on admin edit | `SchedulerControlService.refreshInterval()` + SQS `ModuleRegistry` allow-list |
| Due-poller + atomic claim shape | `PaymentChargeService` (`due_date<=now()`, `claimRow` updateMany status-guard), `CartMaintenanceService` (`expiration_date<=now()`) |
| Send + audit | `MailerService.sendFromTemplate()` → `NotificationLog` PENDING→SENT/FAILED |
| FOLLOW_UP recipient capture (no DRR) | existing live send sites: `lead-notification.service.ts:86`, `low-balance.service.ts:111`, `daily-summary.service.ts:125` |
| Re-entrancy + lifecycle log | Task `isRunning` guard + `ApplicationLogService` |
| Config knobs | `PplSettingsService.getInt` (TTL cache + `invalidate`) |
| DTO/validation | `@IsOptionalNonNull`, nested `ValidateNested` DTOs, `Config*`/`RecipientList` factories |
| Audit | `AdminAuditService` + `buildNotificationTemplateUpdateNote` + snapshot |
| Schedulability flag plumbing | `is_active` patterns: DTO `@IsBoolean`, create data block, `collectScalarUpdates` tuple, both SELECT consts, audit snapshot |
| Anchors that exist today | `Cart.expiration_date`, `PaymentTransaction.due_date`, `Order.paid_in_full_at`, `Shows.date`/`timezone` (date-only, weak) |

---

## 7. Phasing

1. **Schema** — migration in `admin-backend-api`: **`is_schedulable Boolean @default(false)` on `NotificationTemplate`** + **`supports_scheduling Boolean @default(false)` on `TriggerEvent`** + 2 scheduling models + 3 enums; backfill (templates → all false; triggers → the §2.0.4 gate set); mirror every column/model/enum into the other four `schema.prisma`; `db push` each. Seeder sets `is_schedulable: false` on all 18 templates and `supports_scheduling` on the gated triggers.
2. **Admin config** — `is_schedulable` create/update field + audit; `ScheduleRuleDto`; the trigger-ceiling + **attach-gate** (`assertSchedulableForScheduleRule`); predefined matrix leaves `is_schedulable` editable; reject turning it off while enabled rules exist; both SELECT consts carry the flag; SQS publish.
3. **Executor (ANCHOR_RELATIVE)** — registrar/task/service; materialize filters `is_schedulable=true AND is_active=true`; dispatch against **existing anchors** (`PaymentTransaction.due_date`, `Cart.expiration_date`, `Order.paid_in_full_at`, and `Shows.date` with null/TBA guards). End-to-end for email.
4. **RECURRING + FOLLOW_UP** — recurrence computation; **FOLLOW_UP capture at existing send sites snapshotting known recipients (no DRR)**; the **stop-condition** resolver set; occurrence→`NotificationLog` linking + dedupe.
5. **Bundle #21 fix** across the four mailers.
6. **Deferred / later (explicit):** **SMS execution stays SKIPPED** (when #2 lands; flip the send-time gate); **DRR-dependent sends stay deferred** (#3); the **unbuilt client templates + their anchors** (vendor/venue/GSC/electric, event-alert/photos, workshop) which require new templates and a schedulable event/show + workshop datetime anchor.

---

## 8. Verification (end-to-end)

- **Schema** — `prisma migrate` applies in `admin-backend-api`; `db push` succeeds in all four others; the two models + enums + both new boolean columns are mirrored identically.
- **Flag is first-class** — fresh seed: all 18 rows have `is_schedulable=false`; `GET /notification-templates/:id` returns the flag; `GET` list also returns it.
- **Config** — `PUT /notification-templates/:id` with a schedule payload persists rules, enforces the two-tier matrix (predefined recipients stay read-only), and writes one `admin_audit_logs` row per change; `GET /notification-templates/:id` returns the schedules; an SQS refresh is published.
- **Attach-gate** — `PUT` a schedule rule on a template with `is_schedulable=false` ⇒ 400 "schedule rule can only be attached … is_schedulable=true". Flip the flag to true, re-PUT ⇒ rule persists, one audit row per change.
- **Trigger ceiling** — setting `is_schedulable=true` on a template whose trigger has `supports_scheduling=false` ⇒ 400.
- **Flag editable on predefined** — toggling `is_schedulable` on a predefined row succeeds (NOT in the read-only set); `notification_type`/SMS-`subject`/locked channel_config keys still rejected as before.
- **Turn-off guard** — setting `is_schedulable=false` while an enabled `notification_schedules` row exists ⇒ 400.
- **Executor candidate filter** — a rule on an `is_schedulable=false` (or `is_active=false`) template materializes **zero** occurrences.
- **Executor (email, ANCHOR_RELATIVE)** — seed a schedulable template + a rule anchored on `Cart.expiration_date` with offsets `−3d/−1d @ 09:00 America/New_York`, `recipient_source=client_email`, and a `replacements_map` for `{{name}}/{{cart_number}}/{{expiration_date}}`; create a cart with a known expiry **and a non-null `client_email`**; run the worker tick (via the dev manual-trigger route); assert two PENDING occurrences with DST-correct `fire_at` and a populated `recipients_snapshot` (resolved from the cart row), then that the due one dispatches via `MailerService` to the cart's `client_email`, writes a `SENT` `NotificationLog`, and links `occurrence.notification_log_id`. Re-run the tick → **no duplicate** (dedupe_key holds).
- **ANCHOR_RELATIVE null-recipient guard** — a matching cart with `client_email IS NULL` (or `expiration_date IS NULL`) ⇒ occurrence `SKIPPED`, no send attempted.
- **ANCHOR_RELATIVE token-recipient defer** — a rule whose recipient would be a token (no `recipient_source` column on the anchor) is author-able but its occurrences `SKIP` with reason `"recipient requires DRR (#3)"`; documented as deferred.
- **Dynamic edit** — change the rule's `send_time`/offset, confirm the next tick reflects it and **already-SENT occurrences are unchanged**.
- **FOLLOW_UP no-DRR** — fire an existing trigger with a follow-up rule; assert an occurrence is inserted with the **snapshotted recipients/replacements** from the live send site; the poller dispatches that snapshot without any recipient re-resolution.
- **Stop-condition** — a `FOLLOW_UP` rule with `stop_condition=CONTRACT_SIGNED`; sign the contract; assert remaining occurrences flip to `CANCELLED` and nothing further sends.
- **SMS gate** — an SMS rule materializes occurrences but they are `SKIPPED` with the provider-not-integrated reason; **no send attempted**.
- **DRR-deferred** — a token-recipient (`{salesperson}`) template cannot be made end-to-end schedulable; documented as deferred, not exercised.
- **#21** — with an active custom template on a live-dispatched trigger slug, the live send path now selects the **predefined** row deterministically; scheduled path (specific template id) unaffected.
- **Cross-doc consistency** — update the scheduling register `EMAIL_SMS_SCHEDULING_KNOWN_ISSUES.md` (SCH-1 / its #1 "Email & SMS Scheduling" entry) to "in design", referencing base register `EMAIL_SMS_KNOWN_ISSUES.md` #2 (SMS provider) / #3 (DRR) / #21 (live shadowing). Both files exist at the APIs project root (verified). Keep all docs consistent with `EMAIL_SMS_STORY_REVISIONS_V2.md` and the new `EMAIL_SMS_TEMPLATE_INTEGRATION_GUIDE.md`.

---

## 9. Dependencies & open items (record, don't own)

- **Trigger-gate backfill set** (§2.0.4 step 3b) — the six slugs opened (`cart_updated_notification`, `ppl_product_order_payment`, `lead_daily_summary`, `lead_credits_renewed`, `company_user_invitation`, `ppl_subscription_canceled`) are a recommendation; opening `supports_scheduling` on a trigger is a product decision about which events may *ever* be scheduled — confirm before seeding. **Note the seeded receipts/notices on these slugs stay `is_schedulable = false`; the gate enables a future *same-trigger custom* template only.** The reminder examples a dev actually authors (integration guide Example B) live on **new** triggers (`cart_expiration_reminder` and a dunning trigger) seeded with their own `supports_scheduling = true` — those new triggers are the primary reminder pattern and are NOT part of this six-slug backfill.
- **Event/Show date + timezone as a first-class schedulable anchor**, **workshop scheduled-time anchor**, and the **unbuilt client templates** — required for the majority of the client's time-based emails; flagged, not built here. `Shows.date` is date-only/nullable with a `date_to_be_added` TBA flag and no end/move-in/move-out column — show-relative scheduling needs new datetime columns first.
- **SMS provider** (#2) — gates scheduled-SMS dispatch; **explicitly deferred**. SMS occurrences materialize then `SKIPPED`.
- **Dynamic recipient resolution / DRR** (#3) — required for sends whose recipients are **tokens with no column on the anchor/source** (`{salesperson}`, `{all speaker email addresses}`); **explicitly deferred**. Two paths sidestep DRR and ship now: FOLLOW_UP snapshots recipients at the live send site (§4 item 8), and ANCHOR_RELATIVE resolves recipients from a **column on the anchor row** via `recipient_source`/`replacements_map` (§4 item 3). Only token-recipients with no source column remain deferred (those occurrences `SKIP`).
- **"Other relevant system emails" source list** (#4) — no observed source endpoint.
- **Stop-condition resolver set** — the exact closed list (`CONTRACT_SIGNED`, `QUESTION_ANSWERED`, `CART_CONVERTED`, `NONE`, …) is code-controlled; finalize when the worker resolvers are implemented.
- **FOLLOW_UP snapshot retention** — storing resolved recipients/replacements on the occurrence row (`recipients_snapshot`) duplicates PII into the scheduling table; confirm acceptable vs storing only the domain anchor id (which would re-introduce a light recipient lookup at fire time).
- Per project convention, the user reviews and commits each repo; this plan introduces no commits.

---

## 10. Developer integration guide (Template Schedulability Framework)

A template flows through five concepts, each pointing into the next:

```
trigger_event (slug + supports_scheduling)   ← code-controlled catalog
        │  FK: notification_templates.notification_type → trigger_events.slug
        ▼
notification_template (is_predefined + is_schedulable)  ← the renderable email/SMS
        │  (only if is_schedulable = true)
        ▼
notification_schedule (kind + anchor/recurrence/follow-up + tz + stop-condition)
        │  materialized each worker tick
        ▼
notification_schedule_occurrence (fire_at + status)
        │  dispatched via MailerService.sendFromTemplate()
        ▼
NotificationLog (PENDING → SENT/FAILED)
```

- `supports_scheduling` (trigger, code-owned) is the **ceiling**; `is_schedulable` (template) is the **switch**; a `notification_schedule` is **inert** unless its template is `is_schedulable = true`.
- A `notification_schedule` dispatches a **specific** template id, so it is immune to #21; event-triggered immediate sends are not (fixed in §5).

**For the exact values a developer must populate to wire a new (non-seeded) template + schedule end-to-end** — full field reference for `trigger_event` / `notification_template` / `notification_schedule`, the anchors-that-exist-today table, a decision tree, two literal worked examples (FOLLOW_UP "Contract Reminder" and ANCHOR_RELATIVE "Cart Expiration Reminder"), the out-of-scope (SMS/DRR/show-anchor) callouts, and gotchas — **see the companion `EMAIL_SMS_TEMPLATE_INTEGRATION_GUIDE.md`.**
