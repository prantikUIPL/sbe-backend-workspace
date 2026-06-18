# Email & SMS Scheduling — Implementation Plan (Dynamic Scheduling)

**Companion to:** `EMAIL_SMS_SCHEDULING_STORY.md` (the refined story this plan builds) and `EMAIL_SMS_TEMPLATE_INTEGRATION_GUIDE.md` (the per-field "what do I type" wiring cookbook — see §10).
**Date:** 2026-06-18
**Revision (2026-06-18):** Added the first-class `is_schedulable` template flag (+ a `TriggerEvent.supports_scheduling` catalog gate), an explicit per-template **Backfill** mapping (all 18 seeded rows → `is_schedulable = false`), the admin schedule-attach gate, the executor candidate filter, the FOLLOW_UP-without-DRR capture path for existing triggers, and a **Template Schedulability Framework** section pointing to the new companion dev guide. **SMS dispatch and Dynamic Recipient Resolution (DRR) remain explicitly deferred** (§9).
**Revision 2 (2026-06-18, review fixes):** Added `recipient_source` + `replacements_map` columns to `notification_schedules` (§2.1) so ANCHOR_RELATIVE resolves recipients/tokens **from the anchor row** at materialize time — making Example B genuinely end-to-end shippable without DRR (token-only recipients with no anchor column stay DRR-deferred). Changed the admin DTO slot to `schedules?: ScheduleRuleDto[]` to match the `[]` back-relation (§3 item 1). Reconciled the §2.0.4 six-slug trigger-gate backfill with the guide's new-trigger reminder examples (§9). Standardized the known-issues cross-references (§8).
**Revision 3 (2026-06-18, sync-review gap-fill):** Corrected the `follow_up` JSON shape to match the guide §2.3 (`{delayDays, repeatCount:int≥1, frequency?}`, §2.1) and the guide-payload cardinality prose (singular `schedule` object → `schedules: ScheduleRuleDto[]`, §3). Fixed the §8 cross-doc instruction (the scheduling engine is **base #1**, not an SCH-N entry; the frozen base register must not be edited). Added the two RECURRING-annual Internal templates (Employee Birthday, Work Anniversary) to the deferred lists (§4.y, §9). **Closed the executor/dispatch logic gaps:** stable `offset_key`/`sequence_index` occurrence identity + PENDING-recompute (AC-3/AC-4); multi-offset look-ahead materialization window; RECURRING bounded roll-forward; DST-correct wall-clock; `EVENT`-timezone fallback chain; concrete stop-condition resolver queries (folds SCH-4); one-hop `recipient_source` (Payment Due → `order.billing_email`, AC-21) + restricted resolver allow-list; **by-id `notificationTemplateId` dispatch** (the #21-immunity claim made true by construction); catch-up sweep + per-tick caps; retry/backoff; `SENDING` status + reaper; re-materialization invalidation + live-anchor reconcile; FOLLOW_UP two capture modes (incl. the no-send-site **Store Contract Reminder**); SMS-skip via denormalized `channel` column; per-kind validation matrix + every-N-min cron syntax; and the worker-schema anchor-model mirroring prerequisite (`Cart` absent today). New `ppl_settings` knobs and occurrence columns documented in §2.2/§4.3 (see §6).
**Scope decisions (locked with the user, 2026-06-16):** full dynamic model (3 schedule kinds + timezone) · **dedicated tables** for config · coverage limited to **built predefined triggers + anchors that exist today** · **domain-state stop-conditions included**.
**Services touched:** `admin-backend-api` (config + migration owner), `background-worker-service` (executor + the by-id `notificationTemplateId` dispatch path + cc/bcc/reply-to forwarding), and the #21 correctness fix in all four mailer-bearing services.

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

**Prerequisite — the worker schema must carry every anchor model (Cart is absent today).** `background-worker-service/prisma/schema.prisma` has **NO `model Cart`** and no `expiration_date` column (`Order` with `billing_email` exists; `PaymentTransaction.due_date` is present; `Cart` is absent). The materializer query against `prisma.cart` will not compile/run. **Rule:** every `anchor_entity` used by an ANCHOR_RELATIVE rule MUST exist as a model in the worker schema with its `anchor_field` AND its `recipient_source` column. Before Phase 3, **mirror the `Cart` model** (incl. `expiration_date`, `client_email`, `client_first_name`, `client_last_name`, `cart_number`, `status`) and `Shows` into the worker schema and `db push`. Until `Cart` is mirrored, integration-guide Example B is not shippable. (§8 verification: "worker schema contains every anchor model referenced by a seeded/sample rule.")

### 2.1 `notification_schedules` — one row per send-rule
| Column | Type | Notes |
|---|---|---|
| `id` | Int PK (`autoincrement`) | Int PK per schema prefs |
| `notification_template_id` | Int FK → `notification_templates.id` | `onDelete: Cascade`; **target row must have `is_schedulable = true`** (§2.3) |
| `schedule_kind` | enum `NotificationScheduleKind` `{ ANCHOR_RELATIVE, RECURRING, FOLLOW_UP }` | authoritative kind (the template's `schedule_config.default_schedule_kind` is only an advisory hint) |
| `anchor_entity` | enum/string, nullable | e.g. `CART`, `PAYMENT_TRANSACTION`, `ORDER`, `SHOW` (ANCHOR_RELATIVE only) |
| `anchor_field` | String, nullable | e.g. `expiration_date`, `due_date`, `paid_in_full_at`, `date` |
| `recipient_source` | String, nullable | ANCHOR_RELATIVE only: the recipient email field the materializer reads to populate `to[]`. **Two allowed forms only** (validated against a per-anchor allow-list, NOT an expression DSL): (a) a bare own-column name on the anchor model (`client_email` for `CART`, `billing_email` for `ORDER`); (b) a **single documented relation hop** matched against a code-controlled per-anchor map (e.g. `PAYMENT_TRANSACTION → order.billing_email`). Nullable sources are guarded; if the resolved value is null/empty the occurrence is `SKIPPED`. **If recipients are tokens (`{salesperson}`) rather than a column/one-hop on the anchor, this is DRR (#3) → deferred.** See §4.7 and §4 item 3. |
| `replacements_map` | Json, nullable | ANCHOR_RELATIVE only: maps each body/subject `{{token}}` to a **restricted** field reference on the anchor record — NOT a general expression language. Two allowed forms: a bare column name, or a fixed named transform (`FULL_NAME(firstField,lastField)`, `DATE_FMT(field,'pattern')`). e.g. `{ "name": "FULL_NAME(client_first_name,client_last_name)", "cart_number": "cart_number", "expiration_date": "DATE_FMT(expiration_date,'PP')" }`. Rejected at the admin DTO validator (beside `assertPlaceholdersAllowed`) AND at materialize time for any other string. Null column ⇒ substitute `''`. (FOLLOW_UP uses `recipients_snapshot` instead — §2.2.) |
| `offsets` | Json | array of `{ value:int≥0, unit:'days'|'hours', direction:'before'|'after' }`; multi-offset = multiple entries |
| `recurrence` | Json, nullable | RECURRING only: `{ daysOfWeek:[...], time:'HH:MM' }` or `{ intervalDays:int }` |
| `send_time` | String `HH:MM`, nullable | ANCHOR_RELATIVE/FOLLOW_UP time-of-day |
| `timezone` | String | `'EVENT'` or an IANA zone (e.g. `America/New_York`) |
| `follow_up` | Json, nullable | FOLLOW_UP only: `{ delayDays:int≥0, repeatCount:int≥1, frequency? }` where `frequency` is optional (omitted ⇒ series re-fires every `delayDays`) and `frequency ∈ 'daily' \| 'weekly' \| {everyDays:int≥1}`. Matches `EMAIL_SMS_TEMPLATE_INTEGRATION_GUIDE.md` §2.3. |
| `stop_condition` | enum `NotificationStopCondition`, nullable | code-controlled set: `CONTRACT_SIGNED`, `QUESTION_ANSWERED`, `CART_CONVERTED`, … `NONE` |
| `end_window_at` | Timestamptz, nullable | optional hard stop for RECURRING |
| `is_enabled` | Boolean `@default(true)` | |
| `created_at` / `updated_at` | Timestamptz | mirror existing column conventions; `updated_at` is the **re-materialization watermark** — when `schedule.updated_at > occurrence.updated_at` a PENDING occurrence is force-recomputed and stale future PENDING rows are superseded (§4.3). |

> **`channel_config` reaches dispatch (do not silently drop it).** `channel_config = { from_name, reply_to, cc_recipients[], bcc_recipients[] }` is a required EMAIL field (guide §2.2; client NOTE A47 "edit TO, CC, BCC at any time"). The materializer copies it into `recipients_snapshot` (`{ to[], cc[], bcc[], replacements, from_name?, reply_to? }`, §2.2) from the template's `channel_config` (ANCHOR_RELATIVE) or the live send site (FOLLOW_UP), and `sendFromTemplate` (or a new dispatch method) must accept `cc/bcc/from_name/reply_to` and pass them to `sgMail.send` (today it uses a single global `SENDGRID_FROM` with no cc/bcc/replyTo — see §4 item 9). If this is deferred to v1+, it is named as an explicit limitation, not dropped.

#### 2.1.1 Per-kind field matrix (enforced at config time, mirrored as `@ValidateIf` in §3)

| Field | ANCHOR_RELATIVE | RECURRING | FOLLOW_UP |
|---|---|---|---|
| `anchor_entity` / `anchor_field` | **required** | forbidden | forbidden |
| `offsets` (≥1) | **required** | forbidden | forbidden |
| `recipient_source` / `replacements_map` | **required** (or explicit token-defer flag) | n/a | n/a (snapshot at site) |
| `recurrence` | forbidden | **required** | forbidden |
| `follow_up` `{delayDays,repeatCount}` | forbidden | forbidden | **required** |
| `anchor_instance_ref` (at capture) | materialized per anchor row | per-instance only ("until answered") | **required at capture** |
| `timezone` | **required** (`EVENT` or IANA) | **required (IANA only)** — `EVENT` invalid | optional (honored via `send_time`, §4.3) |
| `send_time` | optional | n/a (in `recurrence.time`) | optional |
| `stop_condition` | optional | optional | optional |
| `end_window_at` | n/a | optional | **required when `repeatCount` is null** |

**Every RECURRING / FOLLOW_UP series MUST carry at least one bound** (`end_window_at` OR `repeatCount` OR an *implemented* `stop_condition`); reject an unbounded infinite series at config time (folds SCH-4 into the plan — see §4 item 4).

### 2.2 `notification_schedule_occurrences` — materialized due-sends
| Column | Type | Notes |
|---|---|---|
| `id` | BigInt PK | high-volume table; mirror `NotificationLog.id` (BigInt — the one allowed BigInt exception) |
| `schedule_id` | Int FK → `notification_schedules.id` | `onDelete: Cascade` |
| `anchor_instance_ref` | String, nullable | identifies the specific anchor/bound record (e.g. `cart:123`, `order_product:55`, `contract:456`) for ANCHOR_RELATIVE / per-instance RECURRING / FOLLOW_UP |
| `offset_key` | String, nullable | ANCHOR_RELATIVE: the stable per-offset label (e.g. `-7d`, `-24h`, `+1d`). Part of the dedupe identity so `fire_at` (derived, DST/tz-mutable) is never the identity. Null for calendar-only RECURRING. |
| `sequence_index` | Int, nullable | FOLLOW_UP: the 0-based position in the series; part of the dedupe identity for FOLLOW_UP (no domain anchor row). |
| `channel` | enum `NotificationChannel` | denormalized from the template at materialize time so the dispatch query can filter `channel='EMAIL'` and a separate pass can flip `SMS` rows to `SKIPPED` (§4 item 10) without a template join. |
| `recipients_snapshot` | Json, nullable | The recipients + replacements to dispatch with. Shape: `{ to[], cc[], bcc[], replacements, from_name?, reply_to? }` (§4 item 9 — `channel_config`). **FOLLOW_UP:** resolved at the live send site and snapshotted (§4 item 8). **ANCHOR_RELATIVE:** resolved at materialize time from the anchor row via `recipient_source` + `replacements_map` (§4 item 3 / §2.1). Replayed verbatim at dispatch in both cases. |
| `fire_at` | Timestamptz | resolved absolute send instant (UTC). **Recomputed each tick for PENDING rows** (so admin edits to `send_time`/`timezone`/`offsets` move future sends — AC-3); **never recomputed for `SENT`/`SENDING` rows** (AC-4). |
| `series_anchor_at` | Timestamptz, nullable | FOLLOW_UP: the original trigger instant captured on occurrence 0; every later `fire_at = series_anchor_at + cumulative interval` so a slow/late send never drifts the series (§4 item 8). |
| `anchor_value_at_materialize` | Timestamptz, nullable | ANCHOR_RELATIVE: the anchor-field value observed when the occurrence was materialized, so the reconcile pass (§4.3) can detect a moved/nulled anchor and shift/cancel the unsent occurrence. |
| `status` | enum `{ PENDING, SENDING, SENT, SKIPPED, CANCELLED, FAILED }` `@default(PENDING)` | `SENDING` is the atomic-claim state (`updateMany WHERE {id,status:PENDING} SET status='SENDING'`); a SENDING-reaper (§4 item, concurrency) self-heals crashed claims. |
| `attempt_count` | Int `@default(0)` | retry/backoff bookkeeping (§4 item 3 retry). |
| `next_attempt_at` | Timestamptz, nullable | when a retried (back-to-PENDING) occurrence becomes eligible again. |
| `claimed_at` | Timestamptz, nullable | set at claim time; the SENDING-reaper window is `claimed_at < now() - schedule_sending_stale_minutes`. |
| `dedupe_key` | String `@unique` | idempotency identity built from a **stable** key, never `fire_at`: ANCHOR_RELATIVE = `schedule_id + ':' + anchor_instance_ref + ':' + offset_key`; calendar-only RECURRING = `schedule_id + ':recur:' + fire_at_iso_utc` (anchor_instance_ref empty; populated for per-instance "until answered"); FOLLOW_UP = `schedule_id + ':' + anchor_instance_ref + ':' + sequence_index`. |
| `notification_log_id` | BigInt FK → `notification_logs.id`, nullable | links the actual send |
| `created_at` / `updated_at` | Timestamptz | |

Indexes: `(status, fire_at)` for the due-poller; `(status, next_attempt_at)` for the retry-eligible scan; `(schedule_id)`.

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
   - **Cardinality (resolves the `schedule?` vs `schedules[]` mismatch):** the create/update DTO slot is `schedules?: ScheduleRuleDto[]` (an **array**), matching the `schedules NotificationSchedule[]` back-relation (§2.1) — a single template can carry multiple distinct rules (e.g. one `ANCHOR_RELATIVE` plus one `FOLLOW_UP`). Multi-offset within one rule is still the rule's `offsets` array; multiple *rules* are separate array entries. The worked examples in `EMAIL_SMS_TEMPLATE_INTEGRATION_GUIDE.md` currently use a singular `"schedule": {…}` object; that is illustrative of one rule only. The real DTO key is the array `schedules: ScheduleRuleDto[]` — the guide payloads have been corrected to `"schedules": [ {…} ]` (one array element per rule). The attach-gate (item 7) checks the array is empty unless `is_schedulable=true`.
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
1. **Registrar** — register one **heartbeat cron** whose interval comes from a new `ppl_settings` key `schedule_dispatch_interval_minutes` (default 5, clamped `[1,30]`). Build a **six-field every-N-minutes** cron string `0 */N * * * *` — NOT the daily-hour `0 0 H * * *` shape the cited registrars (`low-balance`) use, which fires once a day. Re-register on SQS refresh via `SchedulerControlService.refreshInterval()` in its own try/catch; reuse the `isRunning` re-entrancy guard.
2. **Task** — wrap `ScheduleDispatchService.runTick()` with the existing `isRunning` re-entrancy guard + `ApplicationLogService` started/completed/failed lifecycle; swallow errors so a tick never throws upward.
3. **Service `runTick()`** — a top-of-tick **SENDING-reaper**, then two phases. The full materialize algorithms are specified in §4.3; the stop-condition resolvers in item 4 below; the summary:
   - **SENDING-reaper (top of `runTick`):** `UPDATE occurrences SET status='PENDING' WHERE status='SENDING' AND claimed_at < now() - schedule_sending_stale_minutes` (new `ppl_settings` key, default 15) so a crash mid-send self-heals. The worker inherits the single-instance deployment contract (worker README §5: `instances:1, maxSurge:0`) — the per-row `updateMany` guard is the in-process guard, the topology is the cross-process guard.
   - **Materialize:** load enabled `notification_schedules` for schedulable+active templates (§4 item 6); per kind, materialize PENDING occurrences keyed by the **stable** `dedupe_key` (§2.2) using the algorithms in §4.3 (ANCHOR_RELATIVE multi-offset look-ahead window; RECURRING bounded roll-forward; FOLLOW_UP from the captured trigger instant, item 8). Reconcile existing PENDING rows against the live anchor each pass (§4.3). All `fire_at` math is **DST-correct wall-clock** via `date-fns-tz` (§4.3).
   - **Dispatch:** select due occurrences `WHERE status='PENDING' AND channel='EMAIL' AND fire_at<=now() AND fire_at >= now() - schedule_dispatch_max_catchup_minutes AND (next_attempt_at IS NULL OR next_attempt_at<=now()) ORDER BY fire_at LIMIT MAX_DISPATCH_PER_RUN`; claim each atomically (`updateMany WHERE {id, status:PENDING} SET status='SENDING', claimed_at=now()`, mirroring `payment-charge` `claimRow`); dispatch via `MailerService.sendFromTemplate()` **by explicit template id** (§4 item 9 / §5), link the resulting `NotificationLog`, mark `SENT`; on failure apply the retry/backoff path (item 3 retry, below). Occurrences whose `fire_at` is older than the catch-up window → `SKIPPED` reason "missed send window (downtime catch-up)" (item 3 catch-up). SMS-channel occurrences are **SKIPPED with reason "SMS provider not integrated"** by a separate pass (item 10) until #2 lands.

   **Catch-up after downtime (proximity-to-event, NOTE A48):** a recovered worker must not blast every missed occurrence at once. New `ppl_settings schedule_dispatch_max_catchup_minutes` (default `1440`=24h, clamped). Sweep at top of each tick: PENDING occurrences with `fire_at < now() - max_catchup_minutes` → `SKIPPED` reason "missed send window (downtime catch-up)", never sent. RECURRING must NOT enumerate every missed past slot — the materializer computes only the next due instant(s) from `now()` forward (cap 1 per schedule per tick). Per-tick `MAX_DISPATCH_PER_RUN` cap (mirror payment-charge `MAX_ROWS_PER_RUN=500`) so a recovery surge can't exhaust SendGrid rate limits; remaining due rows roll to the next tick.

   **Retry / backoff on SendGrid failure:** on dispatch failure do NOT mark `FAILED` immediately — increment `attempt_count`; if `attempt_count < MAX_OCCURRENCE_ATTEMPTS` (const `=3`, mirror payment-charge) set `status` back to `PENDING` with `next_attempt_at = now() + backoff(attempt_count)` where `backoff=[5m,30m,2h]` (capped, optional jitter). Only at max attempts → `status='FAILED'` permanently. **Distinguish hard failures** (no recipients, template inactive/removed, SendGrid 4xx auth/validation) → `FAILED`/`SKIPPED` immediately, **no retry**; from **transient** (429, 5xx, network) → retry path. Backed by the `(status, next_attempt_at)` index (§2.2).
4. **Stop-conditions** — an enumerated resolver set (no admin-authored logic), each a concrete query keyed off `occurrence.anchor_instance_ref`, evaluated **once per tick STRICTLY BEFORE the dispatch select** (so a state that resolved this tick cancels its occurrences before they can fire). The concrete per-condition specs:
   - **`CONTRACT_SIGNED`** → parse `'cart:ID'`, `SELECT status FROM carts WHERE id=ID`; resolved if `status='signed'`.
   - **`CART_CONVERTED`** → in today's schema the cart→`Order` is created on signature, so this is the **same** cart-signed check. Document `CONTRACT_SIGNED` and `CART_CONVERTED` as **aliases on today's schema**, OR drop `CART_CONVERTED` until a distinct state exists.
   - **`QUESTION_ANSWERED`** → parse `'order_product:ID'`, resolved when the count of unanswered dynamic product questions = 0. If the answer table is not yet modelled, mark `QUESTION_ANSWERED` **[dep]** and require the rule to carry an `end_window_at` fallback.
   - **On resolve:** `UPDATE notification_schedule_occurrences SET status='CANCELLED' WHERE schedule_id=S AND anchor_instance_ref=ref AND status='PENDING'`, and stop further RECURRING roll-forward for that instance.
   - **HARD RULE (folds SCH-4 into the plan):** any `stop_condition` other than `NONE` whose resolver is not in an `IMPLEMENTED_STOP_RESOLVERS` const MUST carry a non-null `end_window_at` OR `repeatCount`; reject at config validation. Every RECURRING/FOLLOW_UP series must have at least one bound (`end_window_at` OR `repeatCount` OR an implemented `stop_condition`) — reject an unbounded infinite series at config time (matches §2.1.1).
5. **Dev manual trigger** — optionally add a `POST /manual-trigger/schedule-dispatch/run` route in the existing dev/staging-only `ManualTriggerModule` for testing.
6. **Candidate filter (materialize phase):** the rule-loading query joins to the template and **filters `notification_templates.is_schedulable = true AND is_active = true`**. A disabled flag or inactive template ⇒ no occurrences materialized. This is the executor-side honoring of the same first-class gate the admin enforces.
7. **ANCHOR_RELATIVE — confirmed anchor table** (verified against `admin-backend-api/prisma/schema.prisma`):

   | `anchor_entity` | Model (schema line) | `anchor_field` | `recipient_source` (no-DRR email column) | Type / nullability | Poller predicate to clone | Notes |
   |---|---|---|---|---|---|---|
   | `PAYMENT_TRANSACTION` | `PaymentTransaction` (1919) | `due_date` | `order.billing_email` (**one documented relation hop**, code-controlled map; materializer query `include:{ order:{ select:{ billing_email:true } } }`) | `Timestamptz` NOT NULL, `@@index([status, due_date])` | look-ahead window (see §4.3) | Strongest anchor; proven cron-poll shape. The 2nd ✅-shippable row (satisfies STORY AC-21). If `order` or `billing_email` is null ⇒ occurrence `SKIPPED`. |
   | `CART` | `Cart` (2548) | `expiration_date` | `client_email` (nullable, `:2562`) | `Timestamptz?`, indexed `@@index([expiration_date])` | look-ahead window (see §4.3) | Nullable date AND nullable recipient — guard both; null ⇒ SKIPPED. |
   | `ORDER` | `Order` (1460) | `paid_in_full_at` | `billing_email` (own column, nullable) | `Timestamptz?`, set on completion | n/a (set after event) | **FOLLOW_UP anchors only — NOT a forward ANCHOR_RELATIVE anchor.** `paid_in_full_at` is completion-set and never forward-looking; **reject `direction:'before'`** and do not list it among the in-scope ANCHOR_RELATIVE set. |
   | `SHOW` | `Shows` (2200) — model is **`Shows`**, not `Show` | `date` | no column recipient ⇒ **DRR (#3)** | `@db.Date` (date-only), **nullable**, `date_to_be_added` TBA flag, `timezone VarChar(50)?` | n/a | WEAK: date-only, no time, no end/move-in/out column, AND show-relative recipients are tokens (needs DRR). Deferred — §9. |

   **In-scope ANCHOR_RELATIVE set = `CART` (forward, nullable) + `PAYMENT_TRANSACTION` (forward, NOT NULL).** `ORDER` is FOLLOW_UP-only; `SHOW` is deferred. `fire_at` is computed as DST-correct wall-clock with `date-fns-tz` in the rule timezone (`EVENT` resolution chain — see §4 item 7), then upserted as a PENDING occurrence keyed by the stable `dedupe_key`.

   **`recipient_source` resolution (restricted, no eval):** a bare own-column name, OR a single relation hop matched against a hardcoded per-anchor map — e.g. `PAYMENT_TRANSACTION → { 'order.billing_email': row => row.order?.billing_email }`. The materializer's Prisma query for `PAYMENT_TRANSACTION` includes `include:{ order:{ select:{ billing_email:true } } }`; resolve via the map; a null joined value ⇒ occurrence `SKIPPED` (same null-guard as `Cart.client_email`). `ORDER` may use `billing_email` directly.

   **Recipients + replacements for ANCHOR_RELATIVE (no DRR, when the anchor row carries them).** ANCHOR_RELATIVE has **no existing send site** to snapshot from (unlike FOLLOW_UP, item 8), so the materializer must resolve both the recipient list and the `{{token}}` replacements **from the anchor record itself** using two new columns on `notification_schedules` (§2.1): `recipient_source` (the email field on the anchor model — e.g. `Cart.client_email`, `Order.billing_email`) and `replacements_map` (token → anchor-field expression). At materialize time the poller reads the anchor row, evaluates `recipient_source` → `to[]` and `replacements_map` → `replacements`, and stores them on the occurrence (`recipients_snapshot`) so dispatch replays them exactly like FOLLOW_UP. **This is in scope only when the recipient is a real column on the anchor row** (Cart/Order/PaymentTransaction all carry an email field). If a template's recipients are tokens with no column on the anchor (`{salesperson}`, `{all speaker emails}`), that resolution **is DRR (#3) and stays deferred** — such a schedule is author-able but its occurrences `SKIP` with reason `"recipient requires DRR (#3)"`. Nullable recipient sources (`Cart.client_email` is nullable, `schema.prisma:2562`) are guarded: a null source ⇒ occurrence `SKIPPED`. This keeps the §6/Q4 DRR boundary honest: per-anchor *column* recipients ship now; per-anchor *token* recipients defer.
8. **FOLLOW_UP ships in TWO capture modes (no DRR):**
   - **Mode (1) — SEND-SITE capture** for triggers that already have a worker send site holding both the domain anchor id and the resolved recipient list. Confirmed sites: `lead-notification.service.ts:86` (`lead_assigned_preview`), `low-balance.service.ts:111` (`low_balance_warning`), `daily-summary.service.ts:125` (`lead_daily_summary`).
   - **Mode (2) — ANCHOR-ROW capture** for triggers whose "after" event is a settable datetime column on a domain row. **The one in-scope client FOLLOW_UP — Store Contract Reminder ("unsigned after defined delay, until signed") — has NO contract-sent send site in `background-worker-service`** (grep-confirmed), so it is realized as mode (2): an **after-anchor ANCHOR_RELATIVE rule** on the contract/cart sent-timestamp column, `offset +Nd direction:'after'`, `recipient_source=client_email` (a real column, no DRR), `stop_condition=CONTRACT_SIGNED`. **Rule:** any FOLLOW_UP whose trigger lacks a worker send site is realized as an after-anchor ANCHOR_RELATIVE rule when the after-event is a column; only truly send-site-only triggers use snapshot capture. If no "shared/sent" timestamp column exists on the cart/agreement, add one **NOT NULL on transition** (schema prefs) as a documented prerequisite.

   **Mode (1) capture mechanics (at each FOLLOW_UP-eligible send site):**
   1. **Gate on `SENT`:** condition the occurrence INSERT on `result.status==='SENT'` — `sendFromTemplate` never throws on send failure and returns `{status:'FAILED'}`, so "succeeds" must mean `SENT`, not "did not throw".
   2. **Best-effort insert:** wrap the INSERT in its own try/catch that **only logs** on failure (never rethrows) so a bookkeeping error cannot break the live transactional send.
   3. **Fixed series anchor:** store the original trigger instant on occurrence 0 as `series_anchor_at`; every subsequent `fire_at = series_anchor_at + cumulative interval` (NOT `now()+offset`) so a slow/late send never drifts the series; re-enqueue reads `series_anchor_at` from the prior occurrence. `fire_at` is built as DST-correct wall-clock at the rule's `send_time` in the rule timezone (§4.3) — NOT a bare `now()+delayDays`.
   4. **Recipient snapshot:** capture the exact `to[]/replacements` the site already passed into `recipients_snapshot` (addresses SCH-3 capture-at-trigger).

   **Series identity, spacing, termination:** FOLLOW_UP has no domain anchor row, so the capture site MUST write `anchor_instance_ref` to identify the bound entity (e.g. `'contract:456'`/`'company:789'`) and a `sequence_index` on each occurrence. `dedupe_key` for FOLLOW_UP = `schedule_id + ':' + anchor_instance_ref + ':' + sequence_index` (§2.2). The stop-condition resolver reads `anchor_instance_ref` to know which record to inspect. `follow_up = { delayDays (firstDelay, value≥0), repeatCount: int|null, frequency? }` where `frequency` is the spacing between successive reminders (omitted ⇒ every `delayDays`). **Re-enqueue:** after occurrence N sends `SENT`, if `stop_condition` unresolved AND (`repeatCount` null OR `N<repeatCount`) AND within `end_window_at`, insert occurrence N+1 at `series_anchor_at + N*interval`; else stop. **`end_window_at` is REQUIRED (DTO validation) whenever `repeatCount` is null** so an "until signed" series always has a hard ceiling even if `CONTRACT_SIGNED` misfires (closes SCH-4 concretely; matches §2.1.1).

   The dispatch poller **replays the captured snapshot** — it never re-resolves recipients dynamically (the deferred DRR work, #3). DRR is only needed for NOT-yet-seeded triggers with no send site and no anchor column; those stay deferred.
9. **Dispatch by explicit template id + occurrence→`NotificationLog` linking & dedupe:** the stable `dedupe_key` unique (§2.2) means re-running a tick or re-materializing never produces a duplicate send, and already-SENT occurrences are never rewritten. After dispatch, write the returned `NotificationLog.id` into `occurrence.notification_log_id`.
   - **The "#21-immunity" invariant must be made true by construction.** Today `MailerService.sendFromTemplate` (`background-worker-service/src/notification/mailer.service.ts`) takes `{ notificationType, to[], replacements, exhibitorId }` and resolves via `findFirst({ where:{ notification_type, channel:'EMAIL', is_active:true } })` — **no template-id parameter, no `orderBy`** — so a scheduled send is NOT inherently immune to #21. Add an optional `notificationTemplateId?: number` to `SendFromTemplateOptions`; when present, resolve via `findUnique({ where:{ id: notificationTemplateId } })` and **skip the slug lookup entirely** (assert `channel==='EMAIL'` and `is_active===true`; if now inactive/removed, mark the occurrence `SKIPPED` reason "template inactive/removed" — do NOT fall back to slug). The schedule-dispatch executor MUST pass `occurrence→schedule.notification_template_id` into this field. The slug path keeps the §5 `is_predefined`+`orderBy` fix for the live (non-scheduled) triggers.
   - Also extend `sendFromTemplate` (or a new dispatch method) to accept and forward `cc / bcc / from_name / reply_to` from `recipients_snapshot` to `sgMail.send` (§2.1 `channel_config`, §4 item — channel_config).
10. **SMS stays SKIPPED (mechanically defined, not narrated):** the denormalized `occurrence.channel` column (§2.2, set from the template at materialize time) makes the boundary a query: the dispatch select filters `channel='EMAIL'`, and a **separate pass** flips `channel='SMS'` PENDING rows to `SKIPPED` with reason `"SMS provider not integrated"` — no send attempted (consistent with the deferred SMS-provider scope; there are 0 SMS templates today regardless).
11. **`timezone='EVENT'` resolution fallback chain:** `anchor.timezone` if the anchor model has a non-null timezone column (only `Shows` today, free-form `VarChar(50)` — validate against the IANA set; invalid → default) → else `schedule.timezone` IANA value if set → else system default new `ppl_settings schedule_default_timezone` (default `'America/New_York'`, matching the client's EST intent), log a warning. **Config-validation:** reject `timezone='EVENT'` when the `anchor_entity` has no timezone column (`CART`/`ORDER`/`PAYMENT_TRANSACTION`) AND `schedule.timezone` is unset — so the shippable Cart/Payment cases MUST carry an explicit IANA zone (resolves the gap where the two in-scope anchors `Cart.expiration_date` / `PaymentTransaction.due_date` have no timezone column and `EVENT` was unresolvable). **RECURRING with `timezone='EVENT'` is always invalid** (no event to be relative to) — reject at DTO validation (§4.3, §2.1.1).
12. **Per-anchor selectable-column allow-list (code constant; restricted resolver, no expression DSL):** `recipient_source` and `replacements_map` are validated at config time AND at materialize time against a per-anchor allow-list — a new validator beside `assertPlaceholdersAllowed`. Allowed: (1) a bare column on the anchor model; (2) the fixed named transforms `FULL_NAME(firstField,lastField)` and `DATE_FMT(field,'pattern')`. Any other string is rejected. Null-handling: a null referenced column → `''` for `replacements`; a null/empty resolved `recipient_source` → occurrence `SKIPPED` (extends explicitly to "any required recipient token resolving null"). The allow-list: `CART:[client_email, client_first_name, client_last_name, cart_number, expiration_date, status]`; `ORDER:[billing_email, paid_in_full_at]`; `PAYMENT_TRANSACTION:[due_date, order.billing_email (one-hop)]`. This makes the §2.3 Example-B `replacements_map` resolvable as `FULL_NAME(...)` rather than arbitrary eval.

### 4.3 Materialization algorithms (per kind, with the reconcile + recompute rules)

**Occurrence identity uses a stable `offset_key`, not `fire_at` (AC-3/AC-4).** Each ANCHOR_RELATIVE occurrence carries `offset_key` (`-7d`, `-24h`, `+1d`); `dedupe_key = schedule_id + ':' + anchor_instance_ref + ':' + offset_key` (NOT `fire_at`, which is derived and can collide on `-1d` vs `-24h` or shift on tz/DST recompute). This guarantees exactly one occurrence per (rule, anchor-instance, offset). The materialize loop: for each anchor row, for each offset, **upsert by `(schedule_id, anchor_instance_ref, offset_key)`**. `fire_at` is **recomputed each tick for not-yet-sent rows** so an admin edit of `send_time`/`timezone`/`offsets` (AC-3) updates future `fire_at` while the identity stays stable; **NEVER recompute `fire_at` for `SENT`/`SENDING` rows (AC-4).** State explicitly: **PENDING is always recomputed, SENT is immutable.**

**ANCHOR_RELATIVE — multi-offset look-ahead window** (replaces any "clone the `<=now()` predicate" instruction, which would never select a still-future anchor for a before-anchor send): for each enabled ANCHOR_RELATIVE rule, compute `maxBeforeMs = max over offsets where direction='before'` (value→ms), `maxAfterMs = max over direction='after'`. Clamp both to a configurable ceiling — new `ppl_settings schedule_materialize_horizon_days` (default 45, covers the widest in-scope −35d offset + slack, clamped `[1,180]`). Select anchor rows `WHERE anchor_field BETWEEN now() - maxAfterMs - tick AND now() + maxBeforeMs + tick` (reusing `Cart.@@index([expiration_date])` and `PaymentTransaction.@@index([status, due_date])`). For each selected row, for each offset, compute `fire_at = anchor_field ± offset` at `rule.send_time` resolved in `rule.timezone` via `date-fns-tz` (DST-correct), and UPSERT a PENDING occurrence. The window is the **union of all offsets** so `-30/-7/-1d` all materialize the moment the anchor enters the −30d horizon. Idempotent via the unique `dedupe_key`.

**RECURRING — bounded roll-forward** (e.g. Mon/Thu 11AM until answered): RECURRING materializes **per-schedule** (not per-anchor). Each tick, for each enabled non-stopped RECURRING schedule: find `watermark = latest materialized occurrence.fire_at` for the schedule (or `schedule.created_at` if none); from `recurrence = { daysOfWeek:['MON','THU'], time:'11:00' }` compute, in `rule.timezone` via `date-fns-tz`, every matching instant **strictly after `watermark` and `<= now()+horizon`** (new `ppl_settings schedule_recurring_horizon_days`, default 14, clamped); UPSERT each PENDING. For **"until answered"** the series is **per recipient-instance**: set `anchor_instance_ref='order_product:'+id` to bind it to the product/order instance, materialize **one rolling occurrence at a time per instance**, and stop the roll-forward when the stop-condition resolver reports answered or `end_window_at` passes. Bounded by horizon so the table never grows unboundedly. **RECURRING with `timezone='EVENT'` is INVALID** (no per-record anchor to resolve a zone from) — reject at DTO validation; only IANA zones valid for RECURRING. `dedupe_key` for RECURRING = `schedule_id + ':recur:' + fire_at_iso_utc` (`anchor_instance_ref` empty for calendar-only; populated for per-instance "until answered").

**DST-correct wall-clock** (RECURRING + FOLLOW_UP + ANCHOR_RELATIVE `send_time`): build the send instant as a LOCAL wall-clock datetime (the recurrence/anchor date at `send_time`, e.g. `'YYYY-MM-DD 11:00'`) interpreted in the rule timezone via `date-fns-tz` `zonedTimeToUtc` — **never** by adding fixed UTC intervals (which drift off 11AM local across a DST boundary). FOLLOW_UP `fire_at = (trigger date + follow_up.delayDays)` anchored at the rule's `send_time` resolved in the rule's timezone (DST-correct), matching the ANCHOR_RELATIVE path — NOT a bare `now()+delayDays` (this fixes the §4 item 8 formula, which otherwise drops `send_time`/`timezone`). The chosen direction is to **honor `send_time`/`timezone` on FOLLOW_UP** (the alternative — fire at the trigger instant — would instead require removing `send_time`/`timezone` from FOLLOW_UP-applicable fields in §2.1 / story Kind 3; not chosen). DST edge handling: spring-forward nonexistent local time → normalize forward to the next valid instant; fall-back ambiguous time → choose the earlier (first) occurrence deterministically; add a unit test for a `send_time` landing in the DST gap.

**Re-materialization invalidation on rule edit.** `SchedulerControlService.refreshInterval()` only invalidates `pplSettings` + re-creates the CronJob; it does NOT touch already-materialized occurrences, so an edited rule's stale PENDING rows would still dispatch. Keyed off `schedule.updated_at`: in the materialize phase, for each enabled rule first **CANCEL stale future PENDING** occurrences `WHERE created_at < schedule.updated_at AND fire_at > now()` (reason "superseded by rule edit"), then re-materialize from the current rule. **DELETE/cancel PENDING occurrences whose offset no longer exists** in the edited rule; for a disabled rule (`is_enabled=false`) cancel ALL its future PENDING. **NEVER touch occurrences with `fire_at<=now()` or status in (`SENT`,`SENDING`).** When `schedule.updated_at > occurrence.updated_at` for a PENDING row, force-recompute. The in-flight race is covered by the existing `isRunning` re-entrancy guard + `pplSettings.invalidate()` ordering because materialization is idempotent via the stable `(schedule_id, anchor_instance_ref, offset_key)` — the refresh only needs to land before the NEXT tick, not interrupt the current one.

**Reconcile PENDING against the live anchor each tick** (anchor moved / nulled / invalidated). Store `anchor_value_at_materialize` on the occurrence. At the top of each materialize pass, for every future PENDING ANCHOR_RELATIVE occurrence re-read its anchor row by `anchor_instance_ref`:
- (a) anchor row gone or `anchor_field` now NULL → `CANCELLED` reason "anchor cleared/removed";
- (b) `anchor_field` moved so recomputed `fire_at != occurrence.fire_at` → UPDATE `fire_at` in place (stable key) — so a moved `Cart.expiration_date` / `Order.paid_in_full_at` shifts the unsent reminder;
- (c) anchor no longer qualifies (`cart.status in {expired,signed,void}` for a "before expiry" rule; payment status not `scheduled`) → CANCEL remaining PENDING (reuse the cart-maintenance / payment-charge status fields).

This prevents the double-send (old wrong-day + new correct-day) and stale fires after extension/cancellation; bounded to **future PENDING rows only** (SENT/past untouched).

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
- **Employee Birthday** and **Employee Work Anniversary** (Internal, RECURRING annual per the client list / `EMAIL_SMS_Consolidated_Template_List.xlsx` rows 22-23) — no employee birthdate/hire-date date anchor is modelled today, so the annual recurrence has no anchor to compute from; deferred until such a date column exists.

---

## 5. Layer C — Bundled correctness fix (Known-Issue #21)

Independently agreed to ship "together with the scheduling logic." The live send path selects a template without an `is_predefined` filter or `orderBy`, so an active **custom** template on a dispatched trigger can nondeterministically shadow the predefined one.

**Fix:** add `is_predefined: true` (+ a deterministic `orderBy`) to the template lookup in every `sendFromTemplate`:
- `background-worker-service/src/notification/mailer.service.ts` (`:92-107`)
- `admin-backend-api/src/common/services/mailer.service.ts`
- `external-api-service/src/common/services/mailer.service.ts`
- `exhibitor-backend-api/src/common/services/mailer.service.ts`

**Interaction with `is_schedulable`:**
- **Scheduled sends are immune to #21 — but only *by construction*, not inherently.** The current `MailerService.sendFromTemplate` resolves by slug (`findFirst({ notification_type, channel:'EMAIL', is_active:true })`) with no template-id param and no `orderBy`, so a scheduled send is NOT immune until the by-id path is added. The §4 item 9 change makes it true: `sendFromTemplate` accepts an optional `notificationTemplateId?: number`; the executor passes `occurrence→schedule.notification_template_id`; when present it resolves via `findUnique({ id })` and skips the slug lookup entirely (no fallback — an inactive/removed template marks the occurrence `SKIPPED`). With that change there is no slug-ambiguity for scheduled paths.
- **The flag does not replace the #21 fix** — `is_schedulable` does not filter the live event-triggered (slug) `sendFromTemplate` path; that path is fixed by the `is_predefined`/`orderBy` change. Both ship together so the live (non-scheduled) triggers also send the predefined row deterministically.

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
| Config knobs | `PplSettingsService.getInt` (TTL cache + `invalidate`) — new keys: `schedule_dispatch_interval_minutes` (5), `schedule_materialize_horizon_days` (45), `schedule_recurring_horizon_days` (14), `schedule_dispatch_max_catchup_minutes` (1440), `schedule_sending_stale_minutes` (15), `schedule_default_timezone` (`America/New_York`) |
| DTO/validation | `@IsOptionalNonNull`, nested `ValidateNested` DTOs, `Config*`/`RecipientList` factories |
| Audit | `AdminAuditService` + `buildNotificationTemplateUpdateNote` + snapshot |
| Schedulability flag plumbing | `is_active` patterns: DTO `@IsBoolean`, create data block, `collectScalarUpdates` tuple, both SELECT consts, audit snapshot |
| Anchors that exist today | `Cart.expiration_date`, `PaymentTransaction.due_date`, `Order.paid_in_full_at`, `Shows.date`/`timezone` (date-only, weak) |

---

## 7. Phasing

1. **Schema** — migration in `admin-backend-api`: **`is_schedulable Boolean @default(false)` on `NotificationTemplate`** + **`supports_scheduling Boolean @default(false)` on `TriggerEvent`** + 2 scheduling models + 3 enums (incl. the `SENDING` occurrence status); backfill (templates → all false; triggers → the §2.0.4 gate set); mirror every column/model/enum into the other four `schema.prisma`; `db push` each. **Mirror the anchor models the worker materializer needs (`Cart`, `Shows`) into `background-worker-service/prisma/schema.prisma` — `Cart` is absent today (§2.0.6 prerequisite).** Seeder sets `is_schedulable: false` on all 18 templates and `supports_scheduling` on the gated triggers.
2. **Admin config** — `is_schedulable` create/update field + audit; `ScheduleRuleDto`; the trigger-ceiling + **attach-gate** (`assertSchedulableForScheduleRule`); predefined matrix leaves `is_schedulable` editable; reject turning it off while enabled rules exist; both SELECT consts carry the flag; SQS publish.
3. **Executor (ANCHOR_RELATIVE)** — registrar/task/service; materialize filters `is_schedulable=true AND is_active=true`; multi-offset look-ahead window + stable `offset_key` identity + DST-correct wall-clock; dispatch against the **in-scope forward anchors** (`PaymentTransaction.due_date` with one-hop `order.billing_email`, `Cart.expiration_date` with null guards). `Order.paid_in_full_at` is FOLLOW_UP-only (Phase 4); `Shows.date` deferred. End-to-end for email.
4. **RECURRING + FOLLOW_UP** — RECURRING bounded roll-forward; **FOLLOW_UP in both modes** — mode (1) send-site snapshot capture (no DRR), mode (2) after-anchor ANCHOR_RELATIVE for triggers with no send site (the in-scope **Store Contract Reminder**); the **stop-condition** resolver set; retry/backoff + SENDING-reaper + catch-up sweep; occurrence→`NotificationLog` linking + dedupe (stable `offset_key`/`sequence_index` keys).
5. **Bundle #21 fix** across the four mailers **plus the by-id `notificationTemplateId` dispatch path** so scheduled sends are immune by construction (§4 item 9 / §5).
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
- **#21** — with an active custom template on a live-dispatched trigger slug, the live send path now selects the **predefined** row deterministically; the scheduled path renders the schedule's **`notification_template_id`** even when a custom template shares the slug (by-id dispatch, §4 item 9 / §5).
- **Worker schema parity** — the worker `schema.prisma` contains every anchor model referenced by a seeded/sample rule (notably a mirrored `Cart` with `expiration_date`/`client_email`); a materialize tick against `prisma.cart` compiles and runs.
- **channel_config reaches dispatch** — a scheduled send applies the template's CC / BCC / reply-to / from_name from `recipients_snapshot` (or, if deferred to v1+, the named limitation is documented).
- **Catch-up after downtime** — occurrences older than `schedule_dispatch_max_catchup_minutes` are `SKIPPED` (reason "missed send window"), not sent; a recovery surge respects `MAX_DISPATCH_PER_RUN` and rolls the remainder to the next tick.
- **Retry/backoff** — a transient SendGrid failure re-queues the occurrence to PENDING with `next_attempt_at` set; a hard failure (template inactive, 4xx auth) goes straight to FAILED/SKIPPED with no retry; FAILED only after `MAX_OCCURRENCE_ATTEMPTS`.
- **SENDING-reaper** — an occurrence stuck in `SENDING` past `schedule_sending_stale_minutes` is reset to PENDING and re-sent (at-least-once, idempotent via `dedupe_key`).
- **DST gap** — a `send_time` landing in the spring-forward gap normalizes forward to the next valid instant (unit test); a RECURRING 11:00 series stays at 11:00 local across a DST boundary.
- **Per-kind matrix** — a DTO carrying `offsets` on a RECURRING rule (or `recurrence` on ANCHOR_RELATIVE, or `timezone='EVENT'` on RECURRING) is rejected at config time; an `until-signed` FOLLOW_UP with `repeatCount=null` and no `end_window_at` is rejected.
- **Cross-doc consistency** — update the scheduling register `EMAIL_SMS_SCHEDULING_KNOWN_ISSUES.md` to reflect design-complete status (the register already tracks the scheduling engine as **base #1** at its "Deferred scope" section — do NOT add or rename an SCH-N entry for it). The status flip of base register #1 to "in design" is recorded in the story §7, not as an SCH-N entry; reference base `EMAIL_SMS_KNOWN_ISSUES.md` #2 (SMS provider) / #3 (DRR) / #21 (live shadowing) read-only — that base register is frozen and must not be edited. Both scheduling/base files exist at the APIs project root (verified). Keep all docs consistent with `EMAIL_SMS_STORY_REVISIONS_V2.md` and the new `EMAIL_SMS_TEMPLATE_INTEGRATION_GUIDE.md`.

---

## 9. Dependencies & open items (record, don't own)

- **Trigger-gate backfill set** (§2.0.4 step 3b) — the six slugs opened (`cart_updated_notification`, `ppl_product_order_payment`, `lead_daily_summary`, `lead_credits_renewed`, `company_user_invitation`, `ppl_subscription_canceled`) are a recommendation; opening `supports_scheduling` on a trigger is a product decision about which events may *ever* be scheduled — confirm before seeding. **Note the seeded receipts/notices on these slugs stay `is_schedulable = false`; the gate enables a future *same-trigger custom* template only.** The reminder examples a dev actually authors (integration guide Example B) live on **new** triggers (`cart_expiration_reminder` and a dunning trigger) seeded with their own `supports_scheduling = true` — those new triggers are the primary reminder pattern and are NOT part of this six-slug backfill.
- **Event/Show date + timezone as a first-class schedulable anchor**, **workshop scheduled-time anchor**, an **employee birthdate / hire-date anchor** (for the RECURRING-annual Internal templates **Employee Birthday** and **Employee Work Anniversary**, `EMAIL_SMS_Consolidated_Template_List.xlsx` rows 22-23 — no such date column exists today, so their annual recurrence has nothing to compute from), and the **unbuilt client templates** — required for the majority of the client's time-based emails; flagged, not built here. `Shows.date` is date-only/nullable with a `date_to_be_added` TBA flag and no end/move-in/move-out column — show-relative scheduling needs new datetime columns first.
- **SMS provider** (#2) — gates scheduled-SMS dispatch; **explicitly deferred**. SMS occurrences materialize then `SKIPPED`.
- **Dynamic recipient resolution / DRR** (#3) — required for sends whose recipients are **tokens with no column on the anchor/source** (`{salesperson}`, `{all speaker email addresses}`); **explicitly deferred**. Two paths sidestep DRR and ship now: FOLLOW_UP snapshots recipients at the live send site (§4 item 8), and ANCHOR_RELATIVE resolves recipients from a **column on the anchor row** via `recipient_source`/`replacements_map` (§4 item 3). Only token-recipients with no source column remain deferred (those occurrences `SKIP`).
- **"Other relevant system emails" source list** (#4) — no observed source endpoint.
- **Stop-condition resolver set** — the closed list (`CONTRACT_SIGNED`, `QUESTION_ANSWERED`, `CART_CONVERTED`, `NONE`) is code-controlled; the concrete per-condition queries are specified in §4 item 4. Note `CONTRACT_SIGNED`/`CART_CONVERTED` are **aliases on today's schema** (cart→Order on signature) — either document them as aliases or drop `CART_CONVERTED` until a distinct state exists. `QUESTION_ANSWERED` is `[dep]` until the answer table is modelled (rules must carry an `end_window_at` fallback). The HARD RULE (any non-`NONE` stop-condition without an implemented resolver MUST carry `end_window_at`/`repeatCount`) folds **SCH-4** into the build.
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
- A `notification_schedule` dispatches a **specific** template id (via the `notificationTemplateId` by-id path added in §4 item 9 / §5), so it is immune to #21 by construction; event-triggered immediate sends are not (slug path, fixed in §5).

**For the exact values a developer must populate to wire a new (non-seeded) template + schedule end-to-end** — full field reference for `trigger_event` / `notification_template` / `notification_schedule`, the anchors-that-exist-today table, a decision tree, two literal worked examples (FOLLOW_UP "Contract Reminder" and ANCHOR_RELATIVE "Cart Expiration Reminder"), the out-of-scope (SMS/DRR/show-anchor) callouts, and gotchas — **see the companion `EMAIL_SMS_TEMPLATE_INTEGRATION_GUIDE.md`.**
