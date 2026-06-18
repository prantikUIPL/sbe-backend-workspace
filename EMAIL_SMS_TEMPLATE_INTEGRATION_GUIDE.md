# Email & SMS — Template + Schedule Integration Guide

**Companion to:** `EMAIL_SMS_SCHEDULING_IMPLEMENTATION_PLAN.md` (architecture / build steps), `EMAIL_SMS_SCHEDULING_STORY.md` (story), and `EMAIL_SMS_SCHEDULING_KNOWN_ISSUES.md` (open items, incl. #2 SMS provider and #3 DRR).
**Date:** 2026-06-18
**Purpose:** Give a future developer the exact values to put in every field / column / config to wire a **not-yet-seeded** notification template — and, if it is time-based, its **schedule** — end-to-end. This is the "what do I type" doc; the plan is the "how is it built" doc.

> Conventions verified against `admin-backend-api/prisma/schema.prisma:211-268`, the seeders under `admin-backend-api/src/database/seeds/`, and `background-worker-service/src/notification/mailer.service.ts`. Int PKs (never BigInt except high-volume log tables), `NOT NULL + @default` over nullable, and the user reviews & commits per repo (this guide introduces no commits).

---

## 1. The Schedulability Framework (mental model)

A template flows through five concepts. Read top-to-bottom; each row's left value is an FK or pointer into the next.

```
trigger_event (slug + supports_scheduling)  ← code-controlled catalog; the "event name" + allowed placeholders
        │  FK: notification_templates.notification_type → trigger_events.slug
        ▼
notification_template                       ← the renderable email/SMS; carries is_predefined + is_schedulable
        │  (only if is_schedulable = true)
        ▼
notification_schedule                       ← ONE send-rule: kind + anchor/recurrence/follow-up + timezone + stop-condition
        │  materialized each worker tick
        ▼
notification_schedule_occurrence            ← ONE concrete due-send: fire_at (UTC) + status (PENDING→…)
        │  dispatched via MailerService.sendFromTemplate()
        ▼
NotificationLog                             ← the audit row of the actual send (PENDING → SENT/FAILED)
```

**Key invariants**
- A template needs a trigger; a trigger needs no template (FK is one-directional). **Seed/insert the `trigger_event` first.**
- `trigger_event.supports_scheduling` is the **ceiling** (code-owned): a template may be `is_schedulable = true` only if its trigger has `supports_scheduling = true`.
- `is_schedulable = false` ⇒ the template only fires the moment its event happens (immediate, transactional). **No schedule rows are read.**
- `is_schedulable = true` ⇒ the worker may materialize occurrences for any `notification_schedule` rows attached to that template. **A schedule with no `is_schedulable=true` template is inert.**
- A `notification_schedule` dispatches a **specific** template id, so it is immune to the live-shadowing issue (#21); event-triggered immediate sends are not — see §7 Gotchas.

### Two integration paths

| Path | When | Who sets `is_predefined` | Where values come from |
|---|---|---|---|
| **Seed-time** | Platform template shipped with the product | `true` (forced by seeder, `notification-template.seeder.ts:703`) | Seeder literal + `TEMPLATE_META` + (new) schedule seed map |
| **Admin-created / custom** | Tenant authors a template in the admin UI | `false` (forced by service) | `POST /notification-templates` body, then `PUT …/:id` for schedule |

---

## 2. Complete field reference

### 2.1 `trigger_event` (do this first)

Seeded via `trigger-event.seeder.ts` (idempotent **upsert** by `slug`). No admin CRUD.

| Field | Required | Type / format | Allowed values | Example |
|---|---|---|---|---|
| `slug` | **yes** | `VarChar(150)`, `@unique`, snake_case | new unique slug | `contract_reminder` |
| `label` | **yes** | `VarChar(255)` | human display | `Contract Reminder` |
| `available_placeholders` | no (nullable) | `Json` array of strings | tokens your body uses | `["companyName","contractUrl","dueDate"]` |
| `is_custom` | **yes** | Boolean | always `false` for seeded; `true` only for admin-authored triggers (not built today) | `false` |
| `supports_scheduling` | **yes** (defaulted) | Boolean `@default(false)` | `true` only if a template on this trigger may ever carry a schedule | `true` |

> `supports_scheduling` is the trigger-wide **ceiling**. Triggers carrying time-boxed links or instant security/transactional content (`forgot_password`, `*_reset`, `welcome_email`, …) must stay `false`.

### 2.2 `notification_template`

Columns at `schema.prisma:227-251`. **`is_schedulable` is the new column** added by this work (`Boolean @default(false)`).

| Field | Required | Type / format | Allowed values | Example |
|---|---|---|---|---|
| `notification_type` | **yes** | `VarChar(150)` FK → `trigger_events.slug` | must match an existing trigger slug | `contract_reminder` |
| `template_name` | **yes** | `VarChar(255)` | admin display name | `Contract Reminder` |
| `tag` | **yes** | enum `NotificationTemplateType` | `Store · Internal · Vendor · Product · PPL · System` | `Vendor` |
| `channel` | **yes** | enum `NotificationChannel` | `EMAIL` (only built path) · `SMS` (deferred, see §6) | `EMAIL` |
| `subject` | EMAIL: **yes**; SMS: leave null | `VarChar(255)?` | plain text + `{{token}}` | `Action needed: sign {{companyName}}'s contract` |
| `body` | **yes** | `Text` (NOT NULL) | HTML (built via seeder `join/para/heading/button/...` helpers) + `{{token}}` | `…para('Dear {{companyName}},')…` |
| `language` | **yes** (defaulted) | `VarChar(10) @default("en")` | IETF subtag | `en` |
| `channel_config` | EMAIL: **yes**; SMS: null | `Json?` | EMAIL: `{from_name, reply_to, cc_recipients[], bcc_recipients[]}` | `{ "from_name": "SBE Vendors", "reply_to": "vendors@…" }` |
| `is_predefined` | set by code | Boolean `@default(false)` | seeder forces `true`; service forces `false` — **do not set by hand** | `true` (seed) / `false` (API) |
| `is_schedulable` | **yes** (defaulted) | Boolean `@default(false)` | `true` only if a `notification_schedule` will drive it **and** the trigger's `supports_scheduling = true` | `true` |
| `schedule_config` | no | `Json?` (advisory author hint; read by no dispatcher) | optional intent hint `{default_schedule_kind, default_anchor_entity, default_anchor_field, notes}` — see plan §2.0.3 | `null` |
| `follow_up_config` | no | `Json?` (advisory hint; read by nothing) | leave `null` — use `notification_schedule.follow_up` | `null` |
| `is_active` | **yes** (defaulted) | Boolean `@default(true)` | `true`/`false` | `true` |

> Seeders read `template_name` + `tag` (+ the new `is_schedulable`) from `TEMPLATE_META` (keyed by slug, `notification-template.seeder.ts:74`), not from the template literal. Add a `TEMPLATE_META` entry or the seeder throws (fail-loud guard at `:697-702`).
>
> **PREREQUISITE (do this once, before any of the seed snippets below will compile).** The current `TEMPLATE_META` value type is `Record<string, { template_name: string; tag: NotificationTemplateType }>` (`notification-template.seeder.ts:74`) — it has **no `is_schedulable` key**, so a `TEMPLATE_META[...] = { …, is_schedulable: true }` literal is a TypeScript error until you widen it. As specified in **plan §2.0.5**: (1) widen the value type to `{ template_name: string; tag: NotificationTemplateType; is_schedulable: boolean }`, and (2) change the merge at `:703` from `{ ...template, ...meta, is_predefined: true }` to `{ ...template, ...meta, is_predefined: true, is_schedulable: meta.is_schedulable }`. Without both changes the seeded value is never written. (Existing 18 `TEMPLATE_META` entries must then each gain `is_schedulable: false` — see plan §2.0.4 table.)

### 2.3 `notification_schedule` (only when `is_schedulable = true`)

One row = one send-rule. Columns per `EMAIL_SMS_SCHEDULING_IMPLEMENTATION_PLAN.md §2.1`.

> In the Admin-API payload the schedule slot is the **array** `schedules: ScheduleRuleDto[]` — one element per send-rule (a template may carry several, e.g. one `ANCHOR_RELATIVE` plus one `FOLLOW_UP`). Multi-offset stays inside a single element's `offsets` array, **not** as extra array elements. Each single-row `notification_schedule` seed / JSONC block below maps to **one** element of that array.

| Field | Required | Type / format | Allowed values | Example |
|---|---|---|---|---|
| `notification_template_id` | **yes** | Int FK → `notification_templates.id` | existing template id (must be `is_schedulable=true`) | `42` |
| `schedule_kind` | **yes** | enum `NotificationScheduleKind` | `ANCHOR_RELATIVE · RECURRING · FOLLOW_UP` | `ANCHOR_RELATIVE` |
| `anchor_entity` | ANCHOR_RELATIVE: **yes**; else null | enum/string | `CART · PAYMENT_TRANSACTION · ORDER · SHOW` (anchors that exist today) | `CART` |
| `anchor_field` | ANCHOR_RELATIVE: **yes**; else null | String | the real datetime column on that model (see §3 table) | `expiration_date` |
| `offsets` | ANCHOR_RELATIVE: **yes**; else null | `Json` array | `[{value:int≥0, unit:'days'\|'hours', direction:'before'\|'after'}]` | `[{"value":3,"unit":"days","direction":"before"},{"value":1,"unit":"days","direction":"before"}]` |
| `recurrence` | RECURRING: **yes**; else null | `Json` | **Choose ONE shape:** weekly-on-days → `{daysOfWeek:[0-6], time:'HH:MM'}` (0=Sunday); every-N-days → `{intervalDays:int≥1, time:'HH:MM'}`. Do not combine `daysOfWeek` and `intervalDays` in one row. | `{"intervalDays":1,"time":"08:00"}` |
| `send_time` | ANCHOR_RELATIVE/FOLLOW_UP: optional | `String 'HH:MM'?` | 24h time-of-day | `09:00` |
| `timezone` | **yes** | String | `EVENT` (resolve from anchor record) **or** IANA zone | `America/New_York` |
| `recipient_source` | ANCHOR_RELATIVE: **yes** (or DEFER); else null | String, nullable | the **email column on the anchor record** the materializer reads → `to[]` (e.g. `client_email` for `CART`, `billing_email` for `ORDER`). If recipients are tokens with no column on the anchor (`{salesperson}`) this is **DRR (#3) → deferred** (§6). Nullable column ⇒ occurrence SKIPPED. | `client_email` |
| `replacements_map` | ANCHOR_RELATIVE: **yes**; else null | `Json`, nullable | maps each body/subject `{{token}}` to a field expression on the anchor record; the materializer resolves it from the anchor row to build `replacements`. See the per-example token→field tables in §5. | `{"name":"client_first_name + ' ' + client_last_name","cart_number":"cart_number","expiration_date":"expiration_date"}` |
| `follow_up` | FOLLOW_UP: **yes**; else null | `Json` | `{delayDays:int≥0, repeatCount:int≥1, frequency?}`. `frequency` (optional) is the gap between repeats; if omitted the series re-fires every `delayDays`. **Allowed `frequency` values: `'daily' \| 'weekly' \| {everyDays:int≥1}`.** Omit it for the common case (Example A omits it). | `{"delayDays":2,"repeatCount":3}` |
| `stop_condition` | FOLLOW_UP/RECURRING: optional | enum `NotificationStopCondition` | **code-controlled resolver set — NOT finalized today (plan §9).** Only `NONE` is guaranteed live now. `CONTRACT_SIGNED · QUESTION_ANSWERED · CART_CONVERTED` are the *planned* resolvers and are wired only when the worker resolver for each lands. **If you set a value whose resolver does not exist yet, the series never auto-stops** — bound it with `repeatCount` / `end_window_at` as a backstop. The §5 examples use `CONTRACT_SIGNED`/`CART_CONVERTED` to illustrate the intended shape; treat them as resolver-pending. | `CONTRACT_SIGNED` (resolver-pending) |
| `end_window_at` | RECURRING: optional | `Timestamptz?` | hard stop | `2026-12-31T00:00:00Z` |
| `is_enabled` | **yes** (defaulted) | Boolean `@default(true)` | `true`/`false` | `true` |

---

## 3. Anchors that exist TODAY (real model + field names)

Use ONLY these for `ANCHOR_RELATIVE` until new datetime columns are added. Verified field names below.

| `anchor_entity` | Model | `anchor_field` | Type / caveat |
|---|---|---|---|
| `PAYMENT_TRANSACTION` | `PaymentTransaction` (`schema.prisma:1919`) | `due_date` | `Timestamptz` **NOT NULL**, indexed `(status, due_date)` — **strongest anchor** |
| `CART` | `Cart` (`schema.prisma:2548`) | `expiration_date` | `Timestamptz?` (nullable), indexed — guard null |
| `ORDER` | `Order` (`schema.prisma:1460`) | `paid_in_full_at` | `Timestamptz?`, set only on completion — behaves FOLLOW_UP-like, not forward-looking |
| `SHOW` | `Shows` (`schema.prisma:2200`) | `date` | **`@db.Date` (date-only), nullable**, plus `date_to_be_added` (TBA) flag and free-form `timezone` (`:2235`). Weak: no time component, no end/move-in/move-out column. Guard `date == null` and `date_to_be_added == true`. |

> The model is `Shows`, not `Show`. There is no modelled show end / move-in / move-out / load-in datetime — show-relative emails needing precision require **new columns first** (deferred; see §6 and plan §9).

---

## 4. Decision tree — is this template schedulable, and how?

Answer the questions top-to-bottom in order.

```
Q1. Does this email fire the instant its event happens (receipt, reset link, invite, alert)?
    └─ YES → is_schedulable = FALSE. Stop. No schedule row. (This is ALL 18 seeded templates today.)
    └─ NO  → continue.

Q2. Does the template's trigger have supports_scheduling = true? (the ceiling gate)
    └─ NO  → cannot be scheduled; either open the trigger gate (product decision) or stop.
    └─ YES → continue to pick the kind (Q3/Q4/Q5).

Q3. Is the send timed RELATIVE TO A STORED DATE on a domain record (e.g. "3 days before expiry")?
    └─ YES → schedule_kind = ANCHOR_RELATIVE. Pick anchor_entity + anchor_field from §3.
             ├─ Is that datetime column modelled & populated today?
             │   └─ NO → DEFERRED. Add the datetime column first (out of scope §6). is_schedulable = FALSE.
             └─ Is the RECIPIENT a column on that anchor row (e.g. Cart.client_email)?
                 ├─ YES → set recipient_source + replacements_map + offsets + send_time + timezone.
                 │         No DRR needed. is_schedulable = TRUE.  (← Example B)
                 └─ NO (recipient is a token like {salesperson}) → needs DRR (#3) → DEFERRED (§6).

Q4. Is it a fixed CALENDAR CADENCE (daily digest, weekly reminder) independent of a per-record date?
    └─ YES → schedule_kind = RECURRING. Set recurrence + timezone (+ end_window_at / stop_condition). is_schedulable = TRUE.
             └─ Needs a poller/window built? If the recurring job doesn't exist yet → DEFERRED (e.g. lead_daily_summary).

Q5. Is it a series AFTER an event, repeating UNTIL a domain state resolves ("reminders until signed")?
    └─ YES → schedule_kind = FOLLOW_UP. Set follow_up + stop_condition + timezone.
             └─ Does an existing send site already resolve recipients for this trigger?
                ├─ YES → captured at fire time, no DRR needed. is_schedulable = TRUE.  (← Example A)
                └─ NO  → recipients are tokens → needs DRR (#3) → DEFERRED (§6).
```

---

## 5. Worked examples (literal values, end-to-end)

### Example A — FOLLOW_UP: "Contract Reminder" (until signed)

Reminds a vendor every 2 days, up to 3 times, to sign a contract; stops when signed.

**Step 1 — `trigger_event` seed** (`trigger-event.seeder.ts`)
```ts
{ slug: 'contract_reminder', label: 'Contract Reminder',
  available_placeholders: ['companyName', 'contractUrl', 'dueDate'],
  supports_scheduling: true }
```

**Step 2 — template seed** (`notification-template.seeder.ts`; add `TEMPLATE_META['contract_reminder'] = { template_name: 'Contract Reminder', tag: 'Vendor', is_schedulable: true }`)
> Requires the §2.2 prerequisite (widen the `TEMPLATE_META` value type to include `is_schedulable` and update the `:703` merge — plan §2.0.5) **first**, or this entry will not compile / its `is_schedulable` will not persist.
```ts
{
  notification_type: 'contract_reminder',
  channel: 'EMAIL' as const,
  subject: 'Reminder: sign {{companyName}}\'s contract',
  body: join(
    para('Dear {{companyName}},'),
    para('Your contract is awaiting signature (due {{dueDate}}).'),
    button('Review & Sign', '{{contractUrl}}'),
    signoff('The Small Business Expo Team'),
  ),
  language: 'en',
  is_active: true,
}
// seeder merges: { ...template, ...meta, is_predefined: true, is_schedulable: meta.is_schedulable }
```

**Step 3 — schedule row** (seed the `notification_schedule`, or `PUT` it; `notification_template_id` resolved after the template is created)
```jsonc
{
  "schedule_kind": "FOLLOW_UP",
  "anchor_entity": null, "anchor_field": null, "offsets": null, "recurrence": null,
  "send_time": "09:00",
  "timezone": "America/New_York",
  "follow_up": { "delayDays": 2, "repeatCount": 3 },
  "stop_condition": "CONTRACT_SIGNED",
  "end_window_at": null,
  "is_enabled": true
}
```

**Admin-API payload shape** (`PUT /notification-templates/:id` — attaches the schedule to an existing template)
```jsonc
{
  "is_schedulable": true,
  "schedules": [
    {
      "schedule_kind": "FOLLOW_UP",
      "send_time": "09:00",
      "timezone": "America/New_York",
      "follow_up": { "delayDays": 2, "repeatCount": 3 },
      "stop_condition": "CONTRACT_SIGNED"
    }
  ]
}
```
Worker behavior: when the contract event fires, the existing send site (which already holds recipients) captures the follow-up start into `recipients_snapshot`; the dispatch poller re-enqueues the next occurrence on each success until `repeatCount` (3) is hit or `CONTRACT_SIGNED` cancels the remainder. No DRR needed (recipients were resolved at the live send site). Note `frequency` is omitted, so repeats are spaced by `delayDays` (2). `CONTRACT_SIGNED` is a **resolver-pending** stop_condition (§2.3, plan §9) — `repeatCount: 3` is the hard backstop that bounds the series even before that resolver is wired.

### Example B — ANCHOR_RELATIVE: "Cart Expiration Reminder" on `Cart.expiration_date`

Two nudges at −3 days and −1 day, both at 09:00 New York time.

**Step 1 — `trigger_event` seed**
```ts
{ slug: 'cart_expiration_reminder', label: 'Cart Expiration Reminder',
  available_placeholders: ['name', 'cart_number', 'expiration_date'],
  supports_scheduling: true }
```

**Step 2 — template seed** (`TEMPLATE_META['cart_expiration_reminder'] = { template_name: 'Cart Expiration Reminder', tag: 'Store', is_schedulable: true }`)
> Requires the §2.2 prerequisite (widen the `TEMPLATE_META` value type + update the `:703` merge — plan §2.0.5) **first**.
```ts
{
  notification_type: 'cart_expiration_reminder',
  channel: 'EMAIL' as const,
  subject: 'Your proposal {{cart_number}} expires soon',
  body: join(
    para('Dear {{name}},'),
    para('Proposal {{cart_number}} expires on {{expiration_date}}.'),
    signoff('The Small Business Expo Team'),
  ),
  language: 'en',
  is_active: true,
}
```

**Token → anchor-field mapping (the concrete data the worker needs).** The materializer has no live send site to copy from, so it builds `to[]` and `replacements` straight off the `Cart` row. Map every `{{token}}` in the subject/body to a field expression on `Cart`:

| body/subject token | Cart field expression | note |
|---|---|---|
| recipient (`to[]`) | `client_email` | `schema.prisma:2562`, **nullable** → skip if null |
| `{{name}}` | `client_first_name + ' ' + client_last_name` | no single `name` column on Cart |
| `{{cart_number}}` | `cart_number` | `schema.prisma:2550` |
| `{{expiration_date}}` | `expiration_date` | the anchor field itself |

**Step 3 — schedule row**
```jsonc
{
  "schedule_kind": "ANCHOR_RELATIVE",
  "anchor_entity": "CART",
  "anchor_field": "expiration_date",
  "recipient_source": "client_email",
  "replacements_map": {
    "name": "client_first_name + ' ' + client_last_name",
    "cart_number": "cart_number",
    "expiration_date": "expiration_date"
  },
  "offsets": [
    { "value": 3, "unit": "days", "direction": "before" },
    { "value": 1, "unit": "days", "direction": "before" }
  ],
  "send_time": "09:00",
  "timezone": "America/New_York",
  "recurrence": null, "follow_up": null,
  "stop_condition": "CART_CONVERTED",
  "end_window_at": null,
  "is_enabled": true
}
```

**Admin-API payload shape**
```jsonc
{
  "is_schedulable": true,
  "schedules": [
    {
      "schedule_kind": "ANCHOR_RELATIVE",
      "anchor_entity": "CART",
      "anchor_field": "expiration_date",
      "recipient_source": "client_email",
      "replacements_map": {
        "name": "client_first_name + ' ' + client_last_name",
        "cart_number": "cart_number",
        "expiration_date": "expiration_date"
      },
      "offsets": [
        { "value": 3, "unit": "days", "direction": "before" },
        { "value": 1, "unit": "days", "direction": "before" }
      ],
      "send_time": "09:00",
      "timezone": "America/New_York",
      "stop_condition": "CART_CONVERTED"
    }
  ]
}
```
Worker behavior: each tick finds carts whose `expiration_date` falls in the offset windows, computes `fire_at` with `date-fns-tz` (DST-correct) in `America/New_York`, then resolves the recipient from `recipient_source` (`Cart.client_email`) and the `{{token}}` replacements from `replacements_map` against the cart row, snapshotting both onto the occurrence (so dispatch needs no re-resolution). It upserts PENDING occurrences keyed by `dedupe_key` and dispatches the due ones via `MailerService.sendFromTemplate()`. Because `Cart.expiration_date` **and** `Cart.client_email` are nullable, the materializer **SKIPS** carts where either is null. (`CART_CONVERTED` is a resolver-pending stop_condition — §2.3; the two `offsets` are the real backstop, so the series is naturally finite even before that resolver lands.)

> **Why this is in scope (and where it would NOT be).** Example B is end-to-end shippable precisely because the recipient is a **column on the anchor row** (`Cart.client_email`) and every token maps to a `Cart` field — no dynamic recipient lookup is needed. If instead the recipient were a token like `{salesperson}` with no column on the anchor, resolving it would be **DRR (#3) and the schedule would be author-able but its occurrences would SKIP** until DRR lands (see §6 and the decision tree Q3-anchor branch).

---

## 6. OUT OF SCOPE for now (set these to stay forward-compatible)

| Deferred item | What to set today | Why / what unblocks it |
|---|---|---|
| **SMS channel** (provider not integrated, #2) | SMS templates can be introduced **only via the seeder (predefined path)** — the admin create endpoint is **EMAIL-only** (`SUPPORTED_TEMPLATE_CHANNELS` / `@IsIn` restricts `POST /notification-templates` to `EMAIL`, `service.ts:229`), so do **not** try to `POST` an SMS template (it returns 400). For a seeded SMS template you may attach a schedule, but the dispatcher **materializes occurrences then marks them `SKIPPED` ("SMS provider not integrated")**. Leave `subject` null, `channel_config` null. | `mailer.service.ts` hardcodes `channel:'EMAIL'` and has no SMS sender; the admin create path also rejects non-EMAIL. When #2 lands, flip the send-time gate; no schema change needed. |
| **Dynamic Recipient Resolution / DRR** (#3) | In scope today: **FOLLOW_UP** with an existing send site (recipients captured there), and **ANCHOR_RELATIVE** where the recipient is a **column on the anchor row** (e.g. `Cart.client_email`) declared via `recipient_source`. Do NOT author schedules whose recipients are tokens like `{salesperson}` / `{all speaker emails}` with no column on the anchor — those need DRR. | FOLLOW_UP replays recipients captured at the live send site; ANCHOR_RELATIVE resolves them from the anchor column at materialize time (`recipient_source` + `replacements_map`). Token-only recipients (no source column) have no resolver yet — occurrences SKIP. |
| **Show end / move-in / move-out / workshop time anchors** | Do not point `ANCHOR_RELATIVE` at non-existent columns. Only `Shows.date` (date-only, nullable) exists. | New datetime columns + backfill required first; flagged in plan §9. |
| **RECURRING jobs without a built poller** (e.g. `lead_daily_summary` digest) | Keep `is_schedulable = false` until the recurring assembler/window exists. | The cadence is conceptual; no daily digest job is built. |

---

## 7. Gotchas

1. **FK ordering** — insert the `trigger_event` **before** the `notification_template`; the FK is `notification_type → trigger_events.slug`. Seed order is already trigger-seeder-then-template-seeder; preserve it.
2. **Create-only seeder** — `notification-template.seeder.ts` skips if a predefined row already exists for `(notification_type, channel, language)` (`:710-726`). A re-run will **not** apply new field values (e.g. flipping `is_schedulable`) to an already-seeded row — change it via the admin API or a migration backfill, not by editing the seeder alone.
3. **Predefined-uniqueness** — at most one predefined row per `(notification_type, channel)`; the seeder throws on a duplicate pair (`:685-694`). No DB constraint backs this (sibling `db push` would drop a partial index), so keep the catalog clean.
4. **`is_predefined` is code-controlled** — seeder forces `true`, the create service forces `false`. Never set it by hand.
5. **Trigger ceiling** — a template can be `is_schedulable = true` only if its `trigger_event.supports_scheduling = true`. The admin service rejects otherwise. Open the trigger gate (a product decision) before marking a template schedulable.
6. **Schedules require `is_schedulable = true`** — a `notification_schedule` attached to a template with `is_schedulable = false` is inert; the worker won't materialize it. Set the flag and the rule together. Turning the flag off while enabled rules exist is rejected.
7. **Live-shadowing (#21)** — for **event-triggered immediate** sends, the live lookup currently has no `is_predefined` filter / `orderBy`, so an active custom template can shadow the predefined one. Scheduled sends dispatch a specific template id and are immune. The #21 fix ships with this work (plan §5).
8. **`schedule_config` / `follow_up_config` JSON columns are advisory only** — read by no dispatcher in any of the five repos. Use them at most as author-intent hints (plan §2.0.3); the `notification_schedule` table is the real store.
9. **Nullable anchors** — `Cart.expiration_date`, `Order.paid_in_full_at`, and `Shows.date` are nullable (and `Shows` has a `date_to_be_added` TBA flag). The materializer must skip records where the anchor is null. `PaymentTransaction.due_date` is the only NOT-NULL anchor.
10. **`db push` fan-out** — `admin-backend-api` owns the migration that adds `is_schedulable` (+ `TriggerEvent.supports_scheduling`) + the two scheduling tables/enums; mirror the columns/models into the other four `schema.prisma` files and `db push` each. Avoid raw-SQL-only constructs (partial/conditional indexes) — `db push` drops anything not expressible in `schema.prisma`.

---

## 8. Quick checklist (copy/paste)

```
[ ] 1. trigger_event: slug, label, available_placeholders, is_custom=false, supports_scheduling=?
[ ] 2. template:      notification_type (=slug), template_name, tag, channel=EMAIL,
                      subject (EMAIL), body, language='en', channel_config (EMAIL),
                      is_active=true, is_schedulable=?
[ ] 3. (seed only) FIRST widen TEMPLATE_META value type + update :703 merge (plan §2.0.5),
                      THEN add TEMPLATE_META[slug] = { template_name, tag, is_schedulable }
[ ] 4. if is_schedulable=true → trigger.supports_scheduling MUST be true
[ ] 5. notification_schedule: notification_template_id, schedule_kind,
                      (ANCHOR_RELATIVE) anchor_entity + anchor_field + offsets
                                        + recipient_source (anchor email column)
                                        + replacements_map (token → anchor field),
                      (RECURRING) recurrence — choose ONE of {daysOfWeek,time}|{intervalDays,time} (+ end_window_at),
                      (FOLLOW_UP) follow_up {delayDays, repeatCount, frequency?},
                      timezone, send_time?, stop_condition? (resolver-pending — bound with repeatCount/end_window_at),
                      is_enabled=true
[ ] 6. mirror the new columns into the 4 sibling schema.prisma + db push each
[ ] 7. SMS? seeder-only (POST is EMAIL-only) + expect SKIPPED.
       Token recipients (no column on anchor)? DEFERRED (DRR #3). Show anchor? DEFERRED.
```
